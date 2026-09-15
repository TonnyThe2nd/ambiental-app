import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:urbaneye_mobile/features/updates/application/app_update_service.dart';
import 'package:urbaneye_mobile/features/updates/application/update_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final bytes = utf8.encode('test APK');
  Map<String, Object> metadata() => {
    'version': '1.0.3',
    'versionCode': 3,
    'apkUrl': 'https://github.com/example/releases/app.apk',
    'sha256': sha256.convert(bytes).toString(),
    'mandatory': false,
  };
  AppUpdate update() => AppUpdate.parse(jsonEncode(metadata()));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-updates-test-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('urbaneye/app_updates'),
          (call) async => directory.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('urbaneye/app_updates'),
          null,
        );
    await directory.delete(recursive: true);
  });

  test('compara versionCode, não a versão textual', () {
    expect(update().isNewerThan(2), isTrue);
    expect(update().isNewerThan(3), isFalse);
    expect(update().isNewerThan(4), isFalse);
  });
  test('rejeita JSON inválido e tipos inválidos', () {
    for (final value in [
      '{',
      '[]',
      '{}',
      jsonEncode({...metadata(), 'mandatory': 'false'}),
      jsonEncode({...metadata(), 'versionCode': '3'}),
      jsonEncode({...metadata(), 'sha256': 'bad'}),
    ]) {
      expect(() => AppUpdate.parse(value), throwsFormatException);
    }
  });
  test('rejeita URLs inseguras ou inválidas', () {
    for (final url in [
      'http://example.com/app.apk',
      'file:///tmp/app.apk',
      'https:',
      'https://user:password@example.com/app.apk',
      'abc',
    ]) {
      expect(
        () => AppUpdate.parse(jsonEncode({...metadata(), 'apkUrl': url})),
        throwsFormatException,
      );
    }
  });
  for (final installed in [2, 3, 4]) {
    test('consulta versão instalada $installed uma única vez', () async {
      var calls = 0;
      final service = AppUpdateService(
        supported: true,
        installedVersion: () async => installed,
        clientFactory: () => MockClient((_) async {
          calls++;
          return http.Response(jsonEncode(metadata()), 200);
        }),
      );
      expect(
        await service.checkOnce(),
        installed == 2 ? isA<AppUpdate>() : isNull,
      );
      await service.checkOnce();
      expect(calls, 1);
    });
  }
  test('falha de rede é reportada sem repetir consulta', () async {
    final service = AppUpdateService(
      supported: true,
      installedVersion: () async => 2,
      clientFactory: () =>
          MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      service.checkOnce(),
      throwsA(isA<http.ClientException>()),
    );
    await expectLater(
      service.checkOnce(),
      throwsA(isA<http.ClientException>()),
    );
  });
  test('timeout de consulta', () async {
    final service = AppUpdateService(
      supported: true,
      installedVersion: () async => 2,
      timeout: const Duration(milliseconds: 10),
      clientFactory: () => MockClient((_) => Completer<http.Response>().future),
    );
    await expectLater(service.checkOnce(), throwsA(isA<TimeoutException>()));
  });
  test('hash incorreto apaga APK e não abre instalador', () async {
    var installed = false;
    final service = AppUpdateService(
      supported: true,
      clientFactory: () =>
          MockClient((_) async => http.Response('corrupted', 200)),
      installer: (_) async {
        installed = true;
      },
    );
    await expectLater(
      service.downloadAndInstall(update(), onProgress: (_) {}),
      throwsFormatException,
    );
    expect(installed, isFalse);
    expect(await directory.list().toList(), isEmpty);
  });
  test(
    'bloqueia downloads simultâneos, valida hash e informa progresso',
    () async {
      final response = Completer<http.Response>();
      var installs = 0;
      final progress = <double?>[];
      final service = AppUpdateService(
        supported: true,
        clientFactory: () => MockClient((_) => response.future),
        installer: (path) async {
          expect(await File(path).readAsBytes(), bytes);
          installs++;
        },
      );
      final first = service.downloadAndInstall(
        update(),
        onProgress: progress.add,
      );
      await expectLater(
        service.downloadAndInstall(update(), onProgress: (_) {}),
        throwsStateError,
      );
      response.complete(http.Response.bytes(bytes, 200));
      await first;
      expect(installs, 1);
      expect(progress.last, 1);
    },
  );
  test('falha no download libera bloqueio para tentar novamente', () async {
    var calls = 0;
    final service = AppUpdateService(
      supported: true,
      clientFactory: () => MockClient((_) async {
        if (++calls == 1) throw http.ClientException('offline');
        return http.Response.bytes(bytes, 200);
      }),
      installer: (_) async {},
    );
    await expectLater(
      service.downloadAndInstall(update(), onProgress: (_) {}),
      throwsA(isA<http.ClientException>()),
    );
    await service.downloadAndInstall(update(), onProgress: (_) {});
  });
  test('limpa apenas APKs temporários', () async {
    await File('${directory.path}/old.apk').writeAsString('old');
    await File('${directory.path}/keep.txt').writeAsString('keep');
    await UpdateStorage().clean();
    expect(await File('${directory.path}/old.apk').exists(), isFalse);
    expect(await File('${directory.path}/keep.txt').exists(), isTrue);
  });
  test('segue redirecionamento HTTPS usado pelo GitHub Releases', () async {
    var calls = 0;
    final service = AppUpdateService(
      supported: true,
      clientFactory: () => MockClient((request) async {
        if (++calls == 1) {
          return http.Response(
            '',
            302,
            headers: {
              'location':
                  'https://release-assets.githubusercontent.com/app.apk',
            },
          );
        }
        expect(request.url.host, 'release-assets.githubusercontent.com');
        return http.Response.bytes(bytes, 200);
      }),
      installer: (_) async {},
    );
    await service.downloadAndInstall(update(), onProgress: (_) {});
    expect(calls, 2);
  });
  test('recusa redirecionamento para HTTP antes de baixar', () async {
    var calls = 0;
    final service = AppUpdateService(
      supported: true,
      clientFactory: () => MockClient((_) async {
        calls++;
        return http.Response(
          '',
          302,
          headers: {'location': 'http://example.com/app.apk'},
        );
      }),
      installer: (_) async => fail('não deve abrir instalador'),
    );
    await expectLater(
      service.downloadAndInstall(update(), onProgress: (_) {}),
      throwsFormatException,
    );
    expect(calls, 1);
  });
  test('outras plataformas não acessam plugins ou rede', () async {
    final service = AppUpdateService(
      supported: false,
      clientFactory: () => throw StateError('não deve criar cliente'),
    );
    expect(await service.checkOnce(), isNull);
  });
}
