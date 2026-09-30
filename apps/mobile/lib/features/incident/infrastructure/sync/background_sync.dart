import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../../../app/app_initializer.dart';

const _syncTask = 'urbaneye.backgroundSync';

/// Tarefa periódica que verifica as áreas de risco com o app fechado.
const proximityTask = 'urbaneye.proximityCheck';

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      final dependencies = await AppInitializer.initialize(
        registerBackground: false,
      );
      if (task == proximityTask) {
        // App fechado: posição atual contra as áreas em cache (funciona sem rede).
        await dependencies.proximity.backgroundCheck();
        return true;
      }
      await dependencies.sync.synchronize();
      await dependencies.proximity.backgroundCheck();
      final pending = await dependencies.repository.pending();
      if (pending.isNotEmpty) {
        final attempts = pending
            .map((item) => item.attempts)
            .reduce((a, b) => a > b ? a : b);
        await BackgroundSync.schedule(attempts: attempts);
      } else {
        await BackgroundSync.schedule(attempts: 0);
      }
      return true;
    } catch (error) {
      debugPrint('Background sync falhou: $error');
      return false;
    }
  });
}

class BackgroundSync {
  static Future<void> initialize() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    await Workmanager().initialize(backgroundSyncDispatcher);
  }

  /// Verificação periódica (mínimo de 15 minutos imposto pelo Android) para alertar
  /// a entrada em áreas de risco mesmo com o app fechado. Exige a permissão de
  /// localização "o tempo todo". No iOS o rastreamento contínuo cobre o segundo plano.
  static Future<void> scheduleProximityChecks() async {
    if (kIsWeb || !Platform.isAndroid) return;
    await Workmanager().registerPeriodicTask(
      'urbaneye-proximity',
      proximityTask,
      frequency: const Duration(minutes: 15),
    );
  }

  static Future<void> schedule({required int attempts}) async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    final delay = attempts <= 0
        ? const Duration(minutes: 5)
        : attempts == 1
        ? const Duration(minutes: 15)
        : const Duration(hours: 1);
    await Workmanager().registerOneOffTask(
      'urbaneye-sync',
      _syncTask,
      initialDelay: delay,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
