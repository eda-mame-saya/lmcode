import 'dart:io';

import 'package:path/path.dart' as p;

/// `xcode-select -p` が指す Xcode から sourcekit-lsp と xcodebuild を解決する。
class SourceKitToolchain {
  const SourceKitToolchain({
    required this.developerDir,
    required this.sourceKitLsp,
    required this.xcodebuild,
  });

  final String developerDir;
  final String sourceKitLsp;
  final String xcodebuild;

  Map<String, String> get environment {
    final env = Map<String, String>.from(Platform.environment);
    env['DEVELOPER_DIR'] = developerDir;
    final toolchainBin = p.dirname(sourceKitLsp);
    final path = env['PATH'] ?? '';
    env['PATH'] = path.isEmpty ? toolchainBin : '$toolchainBin:$path';
    return env;
  }

  static Future<SourceKitToolchain?> resolve() async {
    final selected = await Process.run('/usr/bin/xcode-select', ['-p']);
    if (selected.exitCode != 0) return null;
    final dir = (selected.stdout as String).trim();
    if (dir.isEmpty) return null;
    final lsp = p.join(
      dir,
      'Toolchains',
      'XcodeDefault.xctoolchain',
      'usr',
      'bin',
      'sourcekit-lsp',
    );
    final build = p.join(dir, 'usr', 'bin', 'xcodebuild');
    if (!File(lsp).existsSync() || !File(build).existsSync()) return null;
    return SourceKitToolchain(
      developerDir: dir,
      sourceKitLsp: lsp,
      xcodebuild: build,
    );
  }
}
