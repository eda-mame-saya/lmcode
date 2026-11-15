import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Strata CLI／run config の探索。
abstract final class StrataRuntimePaths {
  static const macAppCliRelative =
      'Contents/Resources/control/bin/strata';

  static const defaultMacAppBundle = '/Applications/Strata.app';

  /// `strata` 実行ファイルを探す。見つかれば絶対パス。
  static Future<String?> resolveCliPath({String? override}) async {
    final explicit = override?.trim() ?? '';
    if (explicit.isNotEmpty) {
      final file = File(explicit);
      if (await file.exists()) return file.absolute.path;
      return null;
    }

    final candidates = <String>[
      if (Platform.isMacOS)
        p.join(defaultMacAppBundle, macAppCliRelative),
      p.join(
        Platform.environment['HOME'] ?? '',
        '.local',
        'bin',
        'strata',
      ),
      if (Platform.isWindows)
        p.join(
          Platform.environment['LOCALAPPDATA'] ?? '',
          'Strata',
          'bin',
          'strata.exe',
        ),
    ];

    for (final path in candidates) {
      if (path.trim().isEmpty) continue;
      final file = File(path);
      if (await file.exists()) return file.absolute.path;
    }

    try {
      final result = await Process.run(
        Platform.isWindows ? 'where' : 'which',
        <String>['strata'],
        runInShell: false,
      );
      if (result.exitCode == 0) {
        final line = (result.stdout as String)
            .split(RegExp(r'\r?\n'))
            .map((e) => e.trim())
            .firstWhere((e) => e.isNotEmpty, orElse: () => '');
        if (line.isNotEmpty && await File(line).exists()) {
          return File(line).absolute.path;
        }
      }
    } catch (_) {}

    return null;
  }

  /// インストール済みモデルの run config（`strata-*.json`）を探す。
  static Future<String?> resolveRunConfigPath({
    String? override,
    String? cliPath,
  }) async {
    final explicit = override?.trim() ?? '';
    if (explicit.isNotEmpty) {
      final file = File(explicit);
      if (await file.exists()) return file.absolute.path;
      return null;
    }

    final fromCli = await _runConfigFromModelsList(cliPath);
    if (fromCli != null) return fromCli;

    final home = Platform.environment['HOME'] ?? '';
    final installDir = p.join(home, '.local', 'share', 'strata', 'install');
    final dir = Directory(installDir);
    if (!await dir.exists()) return null;

    final matches = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('strata-') &&
          name.endsWith('.json') &&
          !name.endsWith('.bak')) {
        matches.add(entity);
      }
    }
    if (matches.isEmpty) return null;
    matches.sort((a, b) => a.path.compareTo(b.path));
    return matches.first.absolute.path;
  }

  static Future<String?> _runConfigFromModelsList(String? cliPath) async {
    final cli = cliPath?.trim() ?? '';
    if (cli.isEmpty) return null;
    try {
      final result = await Process.run(
        cli,
        <String>['models', 'list', '--output', 'json'],
        runInShell: false,
      );
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map) return null;
      final models = decoded['models'];
      if (models is! List || models.isEmpty) return null;
      for (final item in models) {
        if (item is! Map) continue;
        final source = '${item['source_config'] ?? ''}'.trim();
        if (source.isEmpty) continue;
        if (await File(source).exists()) return File(source).absolute.path;
      }
    } catch (_) {}
    return null;
  }

  /// run config JSON から `model_name` を読む。
  static Future<String?> readModelNameFromRunConfig(String path) async {
    final decoded = await _readRunConfigMap(path);
    if (decoded == null) return null;
    final name = '${decoded['model_name'] ?? ''}'.trim();
    return name.isEmpty ? null : name;
  }

  /// run config の `--max-context`（なければ models list 相当の値は呼び出し側で補完）。
  static Future<int?> readMaxContextFromRunConfig(String path) async {
    final decoded = await _readRunConfigMap(path);
    if (decoded == null) return null;
    for (final key in const ['args_written', 'args']) {
      final fromArgs = _maxContextFromArgList(decoded[key]);
      if (fromArgs != null) return fromArgs;
    }
    for (final key in const [
      'max_context',
      'max-context',
      'context_tokens',
      'context',
    ]) {
      final n = _positiveInt(decoded[key]);
      if (n != null) return n;
    }
    return null;
  }

  /// CLI `models list --output json` の `context_tokens`（run config 欠落時のフォールバック）。
  static Future<int?> readContextTokensFromModelsList(String? cliPath) async {
    final cli = cliPath?.trim() ?? '';
    if (cli.isEmpty) return null;
    try {
      final result = await Process.run(
        cli,
        <String>['models', 'list', '--output', 'json'],
        runInShell: false,
      );
      if (result.exitCode != 0) return null;
      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map) return null;
      final models = decoded['models'];
      if (models is! List || models.isEmpty) return null;
      for (final item in models) {
        if (item is! Map) continue;
        final n = _positiveInt(item['context_tokens']);
        if (n != null) return n;
      }
    } catch (_) {}
    return null;
  }

  static Future<Map<String, dynamic>?> _readRunConfigMap(String path) async {
    try {
      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static int? _maxContextFromArgList(Object? raw) {
    if (raw is! List) return null;
    for (var i = 0; i < raw.length - 1; i++) {
      final flag = '${raw[i]}'.trim();
      if (flag == '--max-context' || flag == '--ctx-size') {
        return _positiveInt(raw[i + 1]);
      }
    }
    return null;
  }

  static int? _positiveInt(Object? raw) {
    if (raw is int) return raw > 0 ? raw : null;
    if (raw is num) {
      final n = raw.toInt();
      return n > 0 ? n : null;
    }
    final parsed = int.tryParse('$raw'.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }
}
