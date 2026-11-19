import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/coding_library_docs.dart';
import 'coding_dependency_version_resolver.dart';

/// ローカル依存を優先し、不足時のみ版付きでレジストリ／アーカイブから docs を取る。
final class CodingLibraryDocsFetcher {
  CodingLibraryDocsFetcher({
    required this.workspaceRoot,
    http.Client? httpClient,
    this.maxChars = codingLibraryDocsMaxChars,
  }) : _http = httpClient ?? http.Client(),
       _resolver = CodingDependencyVersionResolver(workspaceRoot);

  final String workspaceRoot;
  final int maxChars;
  final http.Client _http;
  final CodingDependencyVersionResolver _resolver;

  static const _timeout = Duration(seconds: 25);

  Future<String> fetch({
    required String library,
    required String query,
    String? version,
    String ecosystem = 'auto',
  }) async {
    final name = library.trim();
    if (name.isEmpty) return 'library が空です';
    final q = query.trim();
    final ecoArg = ecosystem.trim().isEmpty ? 'auto' : ecosystem.trim();

    final resolved = await _resolver.resolve(name, ecosystem: ecoArg);
    final eco = (resolved?.ecosystem ?? _guessEcosystem(ecoArg, name)).toLowerCase();
    var ver = (version?.trim().isNotEmpty ?? false)
        ? version!.trim()
        : (resolved?.version ?? '');

    // 1) ローカル依存ディレクトリの README 等
    final localRoot = resolved?.localRoot;
    if (localRoot != null && localRoot.isNotEmpty) {
      final localBody = await _readLocalDocs(localRoot);
      if (localBody != null && localBody.trim().isNotEmpty) {
        final selected = codingLibraryDocsSelectPassages(
          raw: localBody,
          query: q,
          maxChars: maxChars,
        );
        return codingLibraryDocsFormatResult(
          library: name,
          version: ver.isNotEmpty ? ver : (resolved?.version ?? ''),
          ecosystem: eco,
          source: 'local:${resolved?.sourceHint ?? 'cache'}',
          sourceUrl: '',
          body: selected,
          query: q,
        );
      }
    }

    // 2) ネット（版が無ければレジストリの latest／要求版）
    try {
      final remote = (eco == 'npm' || eco == 'node' || eco == 'js')
          ? await _fetchNpm(name, ver)
          : (eco == 'pypi' || eco == 'python' || eco == 'pip')
              ? await _fetchPypi(name, ver)
              : await _fetchPub(name, ver);
      if (remote == null) {
        return _fail(
          library: name,
          version: ver,
          ecosystem: eco,
          message:
              'docs を取得できませんでした（ローカル未配置・ネット失敗）。'
              'hover / go_to_definition または依存のインストールを確認してください。',
        );
      }
      final selected = codingLibraryDocsSelectPassages(
        raw: remote.body,
        query: q,
        maxChars: maxChars,
      );
      return codingLibraryDocsFormatResult(
        library: name,
        version: remote.version.isNotEmpty ? remote.version : ver,
        ecosystem: eco,
        source: remote.source,
        sourceUrl: remote.url,
        body: selected,
        query: q,
      );
    } catch (e) {
      return _fail(
        library: name,
        version: ver,
        ecosystem: eco,
        message: '取得失敗: $e',
      );
    }
  }

  String _guessEcosystem(String ecoArg, String name) {
    final a = ecoArg.toLowerCase();
    if (a != 'auto' && a.isNotEmpty) return a;
    if (name.startsWith('@')) return 'npm';
    return 'dart';
  }

  Future<String?> _readLocalDocs(String root) async {
    final buf = StringBuffer();
    for (final rel in const [
      'README.md',
      'README.MD',
      'readme.md',
      'CHANGELOG.md',
      'CHANGELOG.MD',
      'changelog.md',
      'example/README.md',
      'example/main.dart',
      'example/example.dart',
      'example/lib/main.dart',
    ]) {
      final file = File(p.join(root, rel));
      if (!await file.exists()) continue;
      try {
        final text = await file.readAsString();
        if (text.trim().isEmpty) continue;
        buf
          ..writeln('## $rel')
          ..writeln(text.trim())
          ..writeln();
      } catch (_) {}
    }
    final out = buf.toString().trim();
    return out.isEmpty ? null : out;
  }

  Future<_RemoteDocs?> _fetchPub(String name, String version) async {
    var ver = version;
    if (ver.isEmpty) {
      final meta = await _getJson(
        Uri.parse('https://pub.dev/api/packages/${Uri.encodeComponent(name)}'),
      );
      if (meta == null) return null;
      final latest = meta['latest'];
      if (latest is Map) {
        ver = '${latest['version'] ?? ''}'.trim();
      }
    }
    if (ver.isEmpty) return null;

    final verMeta = await _getJson(
      Uri.parse(
        'https://pub.dev/api/packages/${Uri.encodeComponent(name)}'
        '/versions/${Uri.encodeComponent(ver)}',
      ),
    );
    if (verMeta == null) return null;
    final archiveUrl = '${verMeta['archive_url'] ?? ''}'.trim();
    if (archiveUrl.isEmpty) return null;

    final bytes = await _getBytes(Uri.parse(archiveUrl));
    if (bytes == null) return null;
    final extracted = _extractDocFilesFromArchive(bytes);
    if (extracted == null || extracted.trim().isEmpty) {
      final pubspec = verMeta['pubspec'];
      final desc = pubspec is Map
          ? '${pubspec['description'] ?? ''}'.trim()
          : '';
      if (desc.isEmpty) return null;
      return _RemoteDocs(
        version: ver,
        source: 'pub.dev:pubspec',
        url: 'https://pub.dev/packages/$name/versions/$ver',
        body: desc,
      );
    }
    return _RemoteDocs(
      version: ver,
      source: 'pub.dev:archive',
      url: 'https://pub.dev/packages/$name/versions/$ver',
      body: extracted,
    );
  }

  Future<_RemoteDocs?> _fetchNpm(String name, String version) async {
    var ver = version;
    Map<String, dynamic>? verMeta;
    if (ver.isEmpty) {
      final meta = await _getJson(
        Uri.parse('https://registry.npmjs.org/${_npmEncode(name)}'),
      );
      if (meta == null) return null;
      final distTags = meta['dist-tags'];
      if (distTags is Map) {
        ver = '${distTags['latest'] ?? ''}'.trim();
      }
      final versions = meta['versions'];
      if (ver.isNotEmpty && versions is Map) {
        final entry = versions[ver];
        if (entry is Map) {
          verMeta = Map<String, dynamic>.from(entry);
        }
      }
      final topReadme = '${meta['readme'] ?? ''}'.trim();
      if (topReadme.isNotEmpty && ver.isNotEmpty) {
        return _RemoteDocs(
          version: ver,
          source: 'npm:registry-readme',
          url: 'https://www.npmjs.com/package/$name/v/$ver',
          body: topReadme,
        );
      }
    } else {
      verMeta = await _getJson(
        Uri.parse('https://registry.npmjs.org/${_npmEncode(name)}/$ver'),
      );
    }
    if (ver.isEmpty) return null;
    verMeta ??= await _getJson(
      Uri.parse('https://registry.npmjs.org/${_npmEncode(name)}/$ver'),
    );
    if (verMeta == null) return null;
    final dist = verMeta['dist'];
    final tarball = dist is Map ? '${dist['tarball'] ?? ''}'.trim() : '';
    if (tarball.isEmpty) {
      final desc = '${verMeta['description'] ?? ''}'.trim();
      if (desc.isEmpty) return null;
      return _RemoteDocs(
        version: ver,
        source: 'npm:description',
        url: 'https://www.npmjs.com/package/$name/v/$ver',
        body: desc,
      );
    }
    final bytes = await _getBytes(Uri.parse(tarball));
    if (bytes == null) return null;
    final extracted = _extractDocFilesFromArchive(bytes);
    if (extracted == null || extracted.trim().isEmpty) {
      final desc = '${verMeta['description'] ?? ''}'.trim();
      if (desc.isEmpty) return null;
      return _RemoteDocs(
        version: ver,
        source: 'npm:description',
        url: 'https://www.npmjs.com/package/$name/v/$ver',
        body: desc,
      );
    }
    return _RemoteDocs(
      version: ver,
      source: 'npm:tarball',
      url: 'https://www.npmjs.com/package/$name/v/$ver',
      body: extracted,
    );
  }

  Future<_RemoteDocs?> _fetchPypi(String name, String version) async {
    final path = version.isEmpty
        ? 'https://pypi.org/pypi/${Uri.encodeComponent(name)}/json'
        : 'https://pypi.org/pypi/${Uri.encodeComponent(name)}'
            '/${Uri.encodeComponent(version)}/json';
    final meta = await _getJson(Uri.parse(path));
    if (meta == null) return null;
    final info = meta['info'];
    if (info is! Map) return null;
    final ver = '${info['version'] ?? version}'.trim();
    final summary = '${info['summary'] ?? ''}'.trim();
    final description = '${info['description'] ?? ''}'.trim();
    final home = '${info['home_page'] ?? info['project_url'] ?? ''}'.trim();
    final body = [
      if (summary.isNotEmpty) summary,
      if (description.isNotEmpty) description,
    ].join('\n\n');
    if (body.trim().isEmpty) return null;
    return _RemoteDocs(
      version: ver,
      source: 'pypi:json',
      url: home.isNotEmpty
          ? home
          : 'https://pypi.org/project/$name/${ver.isEmpty ? '' : '$ver/'}',
      body: body,
    );
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  }

  Future<Uint8List?> _getBytes(Uri uri) async {
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    return res.bodyBytes;
  }

  String _npmEncode(String name) {
    if (name.startsWith('@')) {
      final slash = name.indexOf('/');
      if (slash > 0) {
        return '${Uri.encodeComponent(name.substring(0, slash))}'
            '/${Uri.encodeComponent(name.substring(slash + 1))}';
      }
    }
    return Uri.encodeComponent(name);
  }

  String? _extractDocFilesFromArchive(Uint8List bytes) {
    Archive archive;
    try {
      archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    } catch (_) {
      try {
        archive = TarDecoder().decodeBytes(bytes);
      } catch (_) {
        try {
          archive = ZipDecoder().decodeBytes(bytes);
        } catch (_) {
          return null;
        }
      }
    }

    final wanted = <String, String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      final base = p.basename(name).toLowerCase();
      final rel = name.contains('/')
          ? name.substring(name.indexOf('/') + 1)
          : name;
      final relLower = rel.toLowerCase();
      final String? key;
      if (base == 'readme.md' || base == 'readme' || base == 'readme.txt') {
        key = 'README.md';
      } else if (base == 'changelog.md' ||
          base == 'changelog' ||
          base == 'history.md') {
        key = 'CHANGELOG.md';
      } else {
        key = null;
      }
      if (key != null) {
        final content = _archiveFileText(file);
        if (content != null && content.trim().isNotEmpty) {
          wanted.putIfAbsent(key, () => content);
        }
        continue;
      }
      if (relLower == 'example/main.dart' ||
          relLower == 'example/example.dart' ||
          relLower == 'example/readme.md') {
        final content = _archiveFileText(file);
        if (content != null && content.trim().isNotEmpty) {
          wanted.putIfAbsent(rel, () => content);
        }
      }
    }
    if (wanted.isEmpty) return null;
    final buf = StringBuffer();
    for (final entry in wanted.entries) {
      buf
        ..writeln('## ${entry.key}')
        ..writeln(entry.value.trim())
        ..writeln();
    }
    return buf.toString().trim();
  }

  String? _archiveFileText(ArchiveFile file) {
    try {
      final data = file.readBytes() ?? file.content;
      if (data.isEmpty) return null;
      return utf8.decode(data, allowMalformed: true);
    } catch (_) {}
    return null;
  }

  String _fail({
    required String library,
    required String version,
    required String ecosystem,
    required String message,
  }) {
    return codingLibraryDocsFormatResult(
      library: library,
      version: version,
      ecosystem: ecosystem,
      source: 'error',
      sourceUrl: '',
      body: message,
      query: '',
    );
  }
}

final class _RemoteDocs {
  const _RemoteDocs({
    required this.version,
    required this.source,
    required this.url,
    required this.body,
  });

  final String version;
  final String source;
  final String url;
  final String body;
}
