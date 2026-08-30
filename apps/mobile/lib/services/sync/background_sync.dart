import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../../app/app_initializer.dart';

const _syncTask = 'urbaneye.backgroundSync';

@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((_, _) async {
    try {
      final dependencies = await AppInitializer.initialize(
        registerBackground: false,
      );
      await dependencies.sync.synchronize();
      final pending = await dependencies.repository.pending();
      if (pending.isNotEmpty) {
        final attempts = pending
            .map((item) => item.attempts)
            .reduce((a, b) => a > b ? a : b);
        await BackgroundSync.schedule(attempts: attempts);
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
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
