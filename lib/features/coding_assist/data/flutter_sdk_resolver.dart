import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_sdk_resolver.dart';

/// S11 の Dart SDK 設定、または PATH から `flutter` 実行ファイルを解決する。
abstract final class FlutterSdkResolver {
  /// [configuredPath] は S11 `dart_sdk_path`（空なら PATH の `dart`）。
  /// 解決した `dart` の兄弟に `flutter` があればそれを返す。無ければ PATH の `flutter`。
  static Future<String?> resolveFlutterExecutable(
    String? configuredPath,
  ) async {
    final dartPath = await DartSdkResolver.resolveDartExecutable(
      configuredPath,
    );
    if (dartPath != null) {
      final sibling = _siblingFlutter(dartPath);
      if (await File(sibling).exists()) return p.normalize(sibling);
    }
    return _resolveFromPath();
  }

  static String _siblingFlutter(String dartPath) {
    final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
    return p.join(p.dirname(dartPath), name);
  }

  static Future<String?> _resolveFromPath() async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [
        'flutter',
      ], runInShell: true);
      if (result.exitCode != 0) return null;
      final line = (result.stdout as String)
          .split(RegExp(r'[\r\n]+'))
          .map((e) => e.trim())
          .firstWhere((e) => e.isNotEmpty, orElse: () => '');
      if (line.isEmpty) return null;
      final name = p.basename(line).toLowerCase();
      final ok =
          name == 'flutter' || name == 'flutter.bat' || name == 'flutter.exe';
      if (!ok) return null;
      if (!await File(line).exists()) return null;
      return p.normalize(line);
    } catch (_) {
      return null;
    }
  }
}
