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
      if (await _looksLikeDartBinary(configured)) return p.normalize(configured);
      return null;
    }
    if (entity == FileSystemEntityType.directory) {
      final candidates = <String>[
        p.join(configured, 'bin', Platform.isWindows ? 'dart.exe' : 'dart'),
        p.join(configured, Platform.isWindows ? 'dart.exe' : 'dart'),
        // Flutter SDK ルート想定
        p.join(configured, 'bin', 'cache', 'dart-sdk', 'bin',
            Platform.isWindows ? 'dart.exe' : 'dart'),
      ];
      for (final c in candidates) {
        if (await _looksLikeDartBinary(c)) return p.normalize(c);
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
      if (await _looksLikeDartBinary(line)) return p.normalize(line);
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<bool> _looksLikeDartBinary(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final name = p.basename(path).toLowerCase();
    return name == 'dart' || name == 'dart.exe';
  }
}
