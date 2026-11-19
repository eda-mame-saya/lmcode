import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// ワークスペースの lock／package_config から依存の版とローカル根を解決する。
final class CodingDependencyVersionResolver {
  CodingDependencyVersionResolver(this.workspaceRoot);

  final String workspaceRoot;

  /// [library] の解決結果。見つからなければ null。
  Future<CodingResolvedDependency?> resolve(
    String library, {
    String ecosystem = 'auto',
  }) async {
    final name = library.trim();
    if (name.isEmpty) return null;
    final eco = ecosystem.trim().toLowerCase();

    if (eco == 'auto' || eco == 'dart' || eco == 'flutter' || eco == 'pub') {
      final dart = await _resolveDart(name);
      if (dart != null) return dart;
      if (eco != 'auto') return null;
    }
    if (eco == 'auto' || eco == 'npm' || eco == 'node' || eco == 'js') {
      final npm = await _resolveNpm(name);
      if (npm != null) return npm;
      if (eco != 'auto') return null;
    }
    if (eco == 'auto' || eco == 'pypi' || eco == 'python' || eco == 'pip') {
      final py = await _resolvePypi(name);
      if (py != null) return py;
    }
    return null;
  }

  Future<CodingResolvedDependency?> _resolveDart(String name) async {
    final configFile = File(
      p.join(workspaceRoot, '.dart_tool', 'package_config.json'),
    );
    if (await configFile.exists()) {
      try {
        final decoded = jsonDecode(await configFile.readAsString());
        if (decoded is Map) {
          final packages = decoded['packages'];
          if (packages is List) {
            for (final entry in packages) {
              if (entry is! Map) continue;
              if ('${entry['name']}' != name) continue;
              final rootUri = '${entry['rootUri'] ?? ''}';
              final rootPath = _fileUriToPath(rootUri);
              var version = _versionFromPath(rootPath) ?? '';
              if (version.isEmpty && rootPath != null) {
                version = await _readPubspecVersion(rootPath) ?? '';
              }
              return CodingResolvedDependency(
                name: name,
                version: version,
                ecosystem: 'dart',
                localRoot: rootPath,
                sourceHint: 'package_config',
              );
            }
          }
        }
      } catch (_) {}
    }

    final lock = File(p.join(workspaceRoot, 'pubspec.lock'));
    if (await lock.exists()) {
      final version = _parsePubspecLockVersion(
        await lock.readAsString(),
        name,
      );
      if (version != null) {
        return CodingResolvedDependency(
          name: name,
          version: version,
          ecosystem: 'dart',
          localRoot: null,
          sourceHint: 'pubspec.lock',
        );
      }
    }
    return null;
  }

  Future<CodingResolvedDependency?> _resolveNpm(String name) async {
    final pkgDir = _npmPackageDir(name);
    final pkgJson = File(p.join(pkgDir, 'package.json'));
    if (await pkgJson.exists()) {
      try {
        final decoded = jsonDecode(await pkgJson.readAsString());
        if (decoded is Map) {
          final version = '${decoded['version'] ?? ''}'.trim();
          return CodingResolvedDependency(
            name: name,
            version: version,
            ecosystem: 'npm',
            localRoot: pkgDir,
            sourceHint: 'node_modules',
          );
        }
      } catch (_) {}
    }

    final lock = File(p.join(workspaceRoot, 'package-lock.json'));
    if (await lock.exists()) {
      final version = _parsePackageLockVersion(
        await lock.readAsString(),
        name,
      );
      if (version != null) {
        return CodingResolvedDependency(
          name: name,
          version: version,
          ecosystem: 'npm',
          localRoot: null,
          sourceHint: 'package-lock.json',
        );
      }
    }
    return null;
  }

  Future<CodingResolvedDependency?> _resolvePypi(String name) async {
    final lock = File(p.join(workspaceRoot, 'poetry.lock'));
    if (await lock.exists()) {
      final version = _parsePoetryLockVersion(
        await lock.readAsString(),
        name,
      );
      if (version != null) {
        return CodingResolvedDependency(
          name: name,
          version: version,
          ecosystem: 'pypi',
          localRoot: null,
          sourceHint: 'poetry.lock',
        );
      }
    }
    final req = File(p.join(workspaceRoot, 'requirements.txt'));
    if (await req.exists()) {
      final version = _parseRequirementsVersion(
        await req.readAsString(),
        name,
      );
      if (version != null) {
        return CodingResolvedDependency(
          name: name,
          version: version,
          ecosystem: 'pypi',
          localRoot: null,
          sourceHint: 'requirements.txt',
        );
      }
    }
    return null;
  }

  String _npmPackageDir(String name) {
    if (name.startsWith('@')) {
      final slash = name.indexOf('/');
      if (slash > 0) {
        return p.join(
          workspaceRoot,
          'node_modules',
          name.substring(0, slash),
          name.substring(slash + 1),
        );
      }
    }
    return p.join(workspaceRoot, 'node_modules', name);
  }

  static String? _fileUriToPath(String rootUri) {
    final raw = rootUri.trim();
    if (raw.isEmpty) return null;
    try {
      final uri = Uri.parse(raw);
      if (uri.scheme == 'file') return uri.toFilePath();
    } catch (_) {}
    if (p.isAbsolute(raw)) return raw;
    return null;
  }

  static String? _versionFromPath(String? rootPath) {
    if (rootPath == null || rootPath.isEmpty) return null;
    final base = p.basename(rootPath);
    final dash = base.lastIndexOf('-');
    if (dash <= 0 || dash >= base.length - 1) return null;
    final ver = base.substring(dash + 1);
    if (RegExp(r'^\d').hasMatch(ver)) return ver;
    return null;
  }

  static Future<String?> _readPubspecVersion(String rootPath) async {
    final file = File(p.join(rootPath, 'pubspec.yaml'));
    if (!await file.exists()) return null;
    try {
      for (final line in (await file.readAsString()).split('\n')) {
        final m = RegExp(r'^version:\s*(\S+)').firstMatch(line.trimRight());
        if (m != null) return m.group(1)?.trim();
      }
    } catch (_) {}
    return null;
  }

  /// pubspec.lock の `name:\n    version: "x"` 形。
  static String? _parsePubspecLockVersion(String text, String name) {
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!RegExp('^  ${RegExp.escape(name)}:\\s*\$').hasMatch(line)) {
        continue;
      }
      for (var j = i + 1; j < lines.length && j < i + 12; j++) {
        final m = RegExp(
          r'^\s+version:\s*"([^"]+)"',
        ).firstMatch(lines[j]);
        if (m != null) return m.group(1);
        if (RegExp(r'^  \S').hasMatch(lines[j])) break;
      }
    }
    return null;
  }

  static String? _parsePackageLockVersion(String text, String name) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final packages = decoded['packages'];
      if (packages is Map) {
        final key = name.startsWith('@') ? 'node_modules/$name' : 'node_modules/$name';
        final entry = packages[key] ?? packages[name];
        if (entry is Map) {
          final v = '${entry['version'] ?? ''}'.trim();
          if (v.isNotEmpty) return v;
        }
      }
      final deps = decoded['dependencies'];
      if (deps is Map) {
        final entry = deps[name];
        if (entry is Map) {
          final v = '${entry['version'] ?? ''}'.trim();
          if (v.isNotEmpty) return v;
        }
      }
    } catch (_) {}
    return null;
  }

  static String? _parsePoetryLockVersion(String text, String name) {
    final blocks = text.split(RegExp(r'\n\[\[package\]\]\n'));
    for (final block in blocks) {
      final nameMatch = RegExp(
        r'^name\s*=\s*"([^"]+)"',
        multiLine: true,
      ).firstMatch(block);
      if (nameMatch?.group(1) != name) continue;
      final ver = RegExp(
        r'^version\s*=\s*"([^"]+)"',
        multiLine: true,
      ).firstMatch(block);
      return ver?.group(1);
    }
    return null;
  }

  static String? _parseRequirementsVersion(String text, String name) {
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final m = RegExp(
        '^${RegExp.escape(name)}\\s*==\\s*([^\\s;#]+)',
        caseSensitive: false,
      ).firstMatch(line);
      if (m != null) return m.group(1);
    }
    return null;
  }
}

final class CodingResolvedDependency {
  const CodingResolvedDependency({
    required this.name,
    required this.version,
    required this.ecosystem,
    required this.localRoot,
    required this.sourceHint,
  });

  final String name;
  final String version;
  final String ecosystem;
  final String? localRoot;
  final String sourceHint;
}
