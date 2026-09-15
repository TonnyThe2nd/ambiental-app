import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'update_storage.dart';

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.mandatory,
  });

  factory AppUpdate.parse(String source) {
    final data = jsonDecode(source);
    if (data is! Map<String, dynamic> ||
        data['version'] is! String ||
        (data['version'] as String).isEmpty ||
        data['versionCode'] is! int ||
        (data['versionCode'] as int) < 1 ||
        data['apkUrl'] is! String ||
        data['sha256'] is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(data['sha256'] as String) ||
        data['mandatory'] is! bool) {
      throw const FormatException('Metadados de atualização inválidos.');
    }
    final url = Uri.tryParse(data['apkUrl'] as String);
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const FormatException('URL de atualização inválida.');
    }
    return AppUpdate(
      version: data['version'] as String,
      versionCode: data['versionCode'] as int,
      apkUrl: url,
      sha256: (data['sha256'] as String).toLowerCase(),
      mandatory: data['mandatory'] as bool,
    );
  }

  final String version;
  final int versionCode;
  final Uri apkUrl;
  final String sha256;
  final bool mandatory;
  bool isNewerThan(int installed) => versionCode > installed;
}

class AppUpdateService {
  AppUpdateService({
    http.Client Function()? clientFactory,
    Future<int> Function()? installedVersion,
    UpdateStorage? storage,
    Future<void> Function(String)? installer,
    bool? supported,
    this.timeout = const Duration(seconds: 20),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _installedVersion =
           installedVersion ??
           (() async =>
               int.parse((await PackageInfo.fromPlatform()).buildNumber)),
       _storage = storage ?? UpdateStorage(),
       _installer =
           installer ??
           ((path) async {
             await const MethodChannel('urbaneye/app_updates')
                 .invokeMethod<void>('install', {'path': path});
           }),
       supported =
           supported ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  static final metadataUrl = Uri.parse(
    'https://raw.githubusercontent.com/TonnyThe2nd/ambiental-app/master/update/latest.json',
  );
  final http.Client Function() _clientFactory;
  final Future<int> Function() _installedVersion;
  final UpdateStorage _storage;
  final Future<void> Function(String) _installer;
  final bool supported;
  final Duration timeout;
  Future<AppUpdate?>? _check;
  bool _downloading = false;

  // One request per application session, including failures and auth rebuilds.
  Future<AppUpdate?> checkOnce() => _check ??= _checkForUpdate();

  Future<AppUpdate?> _checkForUpdate() async {
    if (!supported) return null;
    final client = _clientFactory();
    try {
      await _storage.clean();
      final installed = await _installedVersion().timeout(timeout);
      final response = await client
          .get(metadataUrl, headers: {'Cache-Control': 'no-cache'})
          .timeout(timeout);
      if (response.statusCode != 200) throw StateError('GitHub indisponível.');
      final update = AppUpdate.parse(response.body);
      return update.isNewerThan(installed) ? update : null;
    } finally {
      client.close();
    }
  }

  Future<void> downloadAndInstall(
    AppUpdate update, {
    required void Function(double?) onProgress,
  }) async {
    if (!supported) {
      throw UnsupportedError('Instalação disponível apenas no Android.');
    }
    if (_downloading) throw StateError('Já existe um download em andamento.');
    // Revalidate even when the caller constructs a descriptor directly.
    AppUpdate.parse(
      jsonEncode({
        'version': update.version,
        'versionCode': update.versionCode,
        'apkUrl': update.apkUrl.toString(),
        'sha256': update.sha256,
        'mandatory': update.mandatory,
      }),
    );
    _downloading = true;
    final client = _clientFactory();
    try {
      await _storage.clean();
      var url = update.apkUrl;
      http.StreamedResponse response;
      var redirects = 0;
      while (true) {
        response = await client
            .send(http.Request('GET', url)..followRedirects = false)
            .timeout(timeout);
        if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
        final location = response.headers['location'];
        await response.stream.drain<void>().timeout(timeout);
        if (location == null || ++redirects > 5) {
          throw StateError('Redirecionamento inválido.');
        }
        url = url.resolve(location);
        if (url.scheme != 'https' ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty ||
            url.hasFragment) {
          throw const FormatException('URL de atualização inválida.');
        }
      }
      if (response.statusCode != 200) {
        throw StateError('Falha ao baixar APK (${response.statusCode}).');
      }
      var received = 0;
      final length = response.contentLength;
      onProgress(null);
      final bytes = response.stream.timeout(timeout).map((chunk) {
        received += chunk.length;
        onProgress(
          length == null || length <= 0
              ? null
              : (received / length).clamp(0, 1),
        );
        return chunk;
      });
      final path = await _storage.save(bytes, update.sha256);
      await _installer(path);
    } finally {
      client.close();
      _downloading = false;
    }
  }
}
