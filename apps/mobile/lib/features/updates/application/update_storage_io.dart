import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class UpdateStorage {
  static const _channel = MethodChannel('urbaneye/app_updates');

  Future<Directory> _directory() async {
    final path = await _channel.invokeMethod<String>('cacheDirectory');
    if (path == null) throw StateError('Cache indisponível.');
    return Directory(path);
  }

  Future<void> clean() async {
    final directory = await _directory();
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is File && entry.path.endsWith('.apk')) await entry.delete();
    }
  }

  Future<String> save(Stream<List<int>> bytes, String expectedHash) async {
    final directory = await _directory();
    final file = File('${directory.path}/update.apk');
    try {
      final sink = file.openWrite();
      try {
        await sink.addStream(bytes);
      } finally {
        await sink.close();
      }
      final actual = await sha256.bind(file.openRead()).first;
      if (actual.toString() != expectedHash) {
        throw const FormatException('SHA-256 inválido. Baixe novamente.');
      }
      return file.path;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }
}
