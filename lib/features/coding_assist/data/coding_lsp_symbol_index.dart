import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/coding_symbol_format.dart';
import 'dart_analysis_server_client.dart';

typedef CodingSymbolSync = Future<void> Function({
  required String absolutePath,
  required String content,
});

/// 1 言語サーバ分の骨格・定義・参照。
class CodingLspSymbolIndex {
  CodingLspSymbolIndex({
    required this.client,
    required this.workspaceRoot,
    required this.syncDocument,
  });

  final DartAnalysisServerClient client;
  final String workspaceRoot;
  final CodingSymbolSync syncDocument;

  Future<String> fileOutline({
    required String relativePath,
    required String absolutePath,
    String? bufferText,
    int? maxEntries,
    int? maxLineChars,
  }) async {
    final text = await _text(absolutePath, bufferText);
    await _sync(absolutePath, text);
    final raw = await client.documentSymbol(
      uri: _uri(absolutePath),
    );
    return CodingSymbolFormat.formatOutline(
      relativePath,
      CodingSymbolFormat.parseOutline(raw),
      maxEntries: maxEntries,
      maxLineChars: maxLineChars,
    );
  }

  Future<String> workspaceSymbol({
    required String query,
    int maxHits = CodingSymbolFormat.maxHits,
  }) async {
    final raw = await client.workspaceSymbol(query: query);
    final hits = _viewHits(CodingSymbolFormat.parseLocations(raw));
    return CodingSymbolFormat.formatWorkspaceHits(hits, maxHits: maxHits);
  }

  Future<String> goToDefinition({
    required String relativePath,
    required String absolutePath,
    required int line,
    int? column,
    String? symbol,
    String? bufferText,
    Map<String, String> openBuffers = const {},
    int? maxLocations,
    int? maxLineChars,
  }) async {
    final located = await _atPosition(
      absolutePath: absolutePath,
      line: line,
      column: column,
      symbol: symbol,
      bufferText: bufferText,
      request: (uri, line, character) => client.definition(
        uri: uri,
        line: line,
        character: character,
      ),
    );
    if (located.error != null) return located.error!;
    final hits = _viewHits(CodingSymbolFormat.parseLocations(located.raw));
    if (hits.isEmpty) return '定義が見つかりません';
    final sources = await _sourcesFor(
      hits,
      openBuffers,
      preferred: {relativePath: located.text},
    );
    return CodingSymbolFormat.formatLocated(
      hits: hits,
      sourceByPath: sources,
      heading: '定義',
      maxHits: maxLocations ?? CodingSymbolFormat.maxDefinitionLocations,
      maxLineChars: maxLineChars,
    );
  }

  Future<String> findReferences({
    required String relativePath,
    required String absolutePath,
    required int line,
    int? column,
    String? symbol,
    String? bufferText,
    Map<String, String> openBuffers = const {},
    int? maxHits,
    int? maxLineChars,
  }) async {
    final located = await _atPosition(
      absolutePath: absolutePath,
      line: line,
      column: column,
      symbol: symbol,
      bufferText: bufferText,
      request: (uri, line, character) => client.references(
        uri: uri,
        line: line,
        character: character,
      ),
    );
    if (located.error != null) return located.error!;
    final hits = _dedupe(
      _viewHits(CodingSymbolFormat.parseLocations(located.raw)),
    );
    if (hits.isEmpty) return '参照がありません';
    final sources = await _sourcesFor(
      hits,
      openBuffers,
      preferred: {relativePath: located.text},
    );
    return CodingSymbolFormat.formatLocated(
      hits: hits,
      sourceByPath: sources,
      heading: '',
      maxHits: maxHits ?? CodingSymbolFormat.maxHits,
      maxLineChars: maxLineChars,
    );
  }

  Future<({String? error, Object? raw, String text})> _atPosition({
    required String absolutePath,
    required int line,
    required int? column,
    required String? symbol,
    required String? bufferText,
    required Future<Object?> Function(String uri, int line, int character)
        request,
  }) async {
    final text = await _text(absolutePath, bufferText);
    final pos = CodingSymbolFormat.resolvePosition(
      text: text,
      line: line,
      column: column,
      symbol: symbol,
    );
    if (pos == null) {
      final name = symbol?.trim() ?? '';
      final hint = name.isEmpty ? 'column' : 'symbol "$name"';
      return (
        error: 'L$line に $hint がありません',
        raw: null,
        text: text,
      );
    }
    await _sync(absolutePath, text);
    final raw = await request(_uri(absolutePath), pos.line, pos.character);
    return (error: null, raw: raw, text: text);
  }

  List<CodingSymbolViewHit> _viewHits(List<CodingRawSymbolLocation> raw) {
    return [
      for (final hit in raw)
        CodingSymbolViewHit(
          path: CodingSymbolFormat.displayPath(hit.uri, workspaceRoot),
          line: hit.line + 1,
          name: hit.name,
          kind: hit.kind,
          container: hit.container,
        ),
    ];
  }

  List<CodingSymbolViewHit> _dedupe(List<CodingSymbolViewHit> hits) {
    final seen = <String>{};
    final out = <CodingSymbolViewHit>[];
    for (final hit in hits) {
      final key = '${hit.path}:${hit.line}';
      if (!seen.add(key)) continue;
      out.add(hit);
    }
    return out;
  }

  Future<Map<String, String>> _sourcesFor(
    List<CodingSymbolViewHit> hits,
    Map<String, String> openBuffers, {
    required Map<String, String> preferred,
  }) async {
    final out = <String, String>{};
    for (final hit in hits) {
      if (out.containsKey(hit.path)) continue;
      final preferredText = preferred[hit.path];
      if (preferredText != null) {
        out[hit.path] = preferredText;
        continue;
      }
      final buffered = _buffer(openBuffers, hit.path);
      if (buffered != null) {
        out[hit.path] = buffered;
        continue;
      }
      final abs = hit.path.startsWith('/') || _isWindowsAbs(hit.path)
          ? hit.path
          : p.normalize(p.join(workspaceRoot, hit.path));
      out[hit.path] = await _readOrEmpty(abs);
    }
    return out;
  }

  bool _isWindowsAbs(String path) => path.length > 2 && path[1] == ':';

  String? _buffer(Map<String, String> openBuffers, String relativePath) {
    if (openBuffers.containsKey(relativePath)) return openBuffers[relativePath];
    final slash = relativePath.replaceAll('\\', '/');
    if (openBuffers.containsKey(slash)) return openBuffers[slash];
    return null;
  }

  Future<String> _text(String absolutePath, String? bufferText) async {
    if (bufferText != null) return bufferText;
    return _readOrEmpty(absolutePath);
  }

  Future<String> _readOrEmpty(String absolutePath) async {
    final file = File(absolutePath);
    if (!await file.exists()) return '';
    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  Future<void> _sync(String absolutePath, String text) async {
    try {
      await syncDocument(absolutePath: absolutePath, content: text);
    } catch (_) {}
  }

  String _uri(String absolutePath) {
    return Uri.file(
      p.normalize(absolutePath),
      windows: Platform.isWindows,
    ).toString();
  }
}
