import 'dart:io';

import 'package:path/path.dart' as p;

/// S11 `dart_sdk_path` または PATH から `dart` 実行ファイルを解決する。
abstract final class DartSdkResolver {
  /// [configuredPath] が空なら PATH 探索。
  /// 成功時は `dart` の絶対パス。失敗時は null。
  static Future<String?> resolveDartExecutable(String? configuredPath) async {
    final configured = configuredPath?.trim() ?? '';
    if (configured.isNotEmpty) {
      final fromConfigured = await _resolveFromConfigured(configured);
      if (fromConfigured != null) return fromConfigured;
    }
    return _resolveFromPath();
  }

  static Future<String?> _resolveFromConfigured(String configured) async {
    final entity = FileSystemEntity.typeSync(configured);
    if (entity == FileSystemEntityType.file) {
      return _asDartExecutable(configured);
    }
    if (entity == FileSystemEntityType.directory) {
      final exe = Platform.isWindows ? 'dart.exe' : 'dart';
      final candidates = <String>[
        p.join(configured, 'bin', exe),
        p.join(configured, exe),
        // Flutter SDK ルート
        p.join(configured, 'bin', 'cache', 'dart-sdk', 'bin', exe),
        // 指定が flutter/bin のとき（Windows は bin 直下に dart.exe が無い）
        p.join(configured, 'cache', 'dart-sdk', 'bin', exe),
        if (Platform.isWindows) p.join(configured, 'dart.bat'),
      ];
      for (final c in candidates) {
        final resolved = await _asDartExecutable(c);
        if (resolved != null) return resolved;
      }
    }
    return null;
  }

  static Future<String?> _resolveFromPath() async {
    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        ['dart'],
        runInShell: true,
      );
      if (result.exitCode != 0) return null;
      final line = (result.stdout as String)
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      if (line.isEmpty) return null;
      final resolved = await _asDartExecutable(line);
      if (resolved != null) return resolved;
    } catch (_) {
      return null;
    }
    return null;
  }

  /// `dart` / `dart.exe` はそのまま。Windows の `dart.bat` は隣の
  /// `cache/dart-sdk/bin/dart.exe` に読み替える（bat は Process.start できない）。
  static Future<String?> _asDartExecutable(String path) async {
    final name = p.basename(path).toLowerCase();
    if (name == 'dart.bat') {
      final exe = p.join(
        p.dirname(path),
        'cache',
        'dart-sdk',
        'bin',
        'dart.exe',
      );
      if (await File(exe).exists()) return p.normalize(exe);
      return null;
    }
    if (name != 'dart' && name != 'dart.exe') return null;
    if (!await File(path).exists()) return null;
    return p.normalize(path);
  }
}
