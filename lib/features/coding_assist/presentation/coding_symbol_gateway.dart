import 'package:path/path.dart' as p;

import '../data/coding_lsp_symbol_index.dart';
import '../domain/coding_harness_settings.dart';
import '../domain/coding_symbol_format.dart';
import '../domain/coding_symbol_index.dart';
import 'widget/coding_dart_completion.dart';
import 'widget/coding_swift_lsp.dart';

/// Dart / Swift の起動済み言語サーバへシンボルツールを振り分ける。
class CodingSymbolGateway implements CodingSymbolIndex {
  CodingSymbolGateway({
    required this.dart,
    required this.swift,
  });

  final CodingDartLspController dart;
  final CodingSwiftLspController swift;

  CodingHarnessSettings harness = CodingHarnessSettings.defaults;

  @override
  void applyHarness(CodingHarnessSettings settings) {
    harness = settings;
  }

  @override
  bool get isReady => dart.symbols != null || swift.symbols != null;

  @override
  Future<String> fileOutline({
    required String relativePath,
    String? bufferText,
  }) {
    return _onFile(relativePath, (index, abs) {
      return index.fileOutline(
        relativePath: relativePath,
        absolutePath: abs,
        bufferText: bufferText,
        maxEntries: harness.maxOutlineEntries,
        maxLineChars: harness.maxSymbolLineChars,
      );
    });
  }

  @override
  Future<String> workspaceSymbol({required String query}) async {
    final q = query.trim();
    if (q.isEmpty) return 'query が空です';
    final dartIndex = dart.symbols;
    final swiftIndex = swift.symbols;
    final cap = dartIndex != null && swiftIndex != null
        ? harness.symbolMaxHitsBoth
        : harness.symbolMaxHits;
    final parts = <String>[];
    if (dartIndex != null) {
      parts.add(await _call(() => dartIndex.workspaceSymbol(query: q, maxHits: cap)));
    }
    if (swiftIndex != null) {
      parts.add(
        await _call(() => swiftIndex.workspaceSymbol(query: q, maxHits: cap)),
      );
    }
    final text = parts.map((e) => e.trim()).where((e) => e.isNotEmpty).join('\n');
    if (text.isEmpty) return 'ヒットなし（query: $q）';
    return text;
  }

  @override
  Future<String> goToDefinition({
    required String relativePath,
    required int line,
    int? column,
    String? symbol,
    String? bufferText,
    Map<String, String> openBuffers = const {},
  }) {
    return _onFile(relativePath, (index, abs) {
      return index.goToDefinition(
        relativePath: relativePath,
        absolutePath: abs,
        line: line,
        column: column,
        symbol: symbol,
        bufferText: bufferText,
        openBuffers: openBuffers,
        maxLocations: harness.maxDefinitionLocations,
        maxLineChars: harness.maxSymbolLineChars,
      );
    });
  }

  @override
  Future<String> findReferences({
    required String relativePath,
    required int line,
    int? column,
    String? symbol,
    String? bufferText,
    Map<String, String> openBuffers = const {},
  }) {
    return _onFile(relativePath, (index, abs) {
      return index.findReferences(
        relativePath: relativePath,
        absolutePath: abs,
        line: line,
        column: column,
        symbol: symbol,
        bufferText: bufferText,
        openBuffers: openBuffers,
        maxHits: harness.symbolMaxHits,
        maxLineChars: harness.maxSymbolLineChars,
      );
    });
  }

  @override
  Future<String> signatureMap(
    List<({String relativePath, String content})> files,
  ) async {
    final buf = StringBuffer();
    var count = 0;
    for (final file in files) {
      if (count >= harness.maxSymbolMapFiles) break;
      if (buf.length >= harness.maxSignatureMapChars) break;
      final index = _indexFor(file.relativePath);
      final root = _rootFor(file.relativePath);
      if (index == null || root == null) continue;
      final outline = await _call(
        () => index.fileOutline(
          relativePath: file.relativePath,
          absolutePath: p.normalize(p.join(root, file.relativePath)),
          bufferText: file.content,
          maxEntries: harness.maxOutlineEntries,
          maxLineChars: harness.maxSymbolLineChars,
        ),
      );
      if (outline.contains('失敗しました') || outline.contains('シンボルがありません')) {
        continue;
      }
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln(outline.trim());
      count++;
    }
    return CodingSymbolFormat.clip(
      buf.toString(),
      harness.maxSignatureMapChars,
    );
  }

  Future<String> _onFile(
    String relativePath,
    Future<String> Function(CodingLspSymbolIndex index, String absolutePath) run,
  ) async {
    final index = _indexFor(relativePath);
    if (index == null) return _offMessage(relativePath);
    final root = _rootFor(relativePath);
    if (root == null) return _offMessage(relativePath);
    final abs = p.normalize(p.join(root, relativePath));
    return _call(() => run(index, abs));
  }

  CodingLspSymbolIndex? _indexFor(String relativePath) {
    final lower = relativePath.toLowerCase();
    if (lower.endsWith('.dart')) return dart.symbols;
    if (lower.endsWith('.swift')) return swift.symbols;
    return null;
  }

  String? _rootFor(String relativePath) {
    final lower = relativePath.toLowerCase();
    if (lower.endsWith('.dart')) return dart.workspaceRoot;
    if (lower.endsWith('.swift')) return swift.workspaceRoot;
    return null;
  }

  String _offMessage(String relativePath) {
    final lower = relativePath.toLowerCase();
    if (lower.endsWith('.dart')) return CodingSymbolFormat.languageOff('Dart');
    if (lower.endsWith('.swift')) {
      return CodingSymbolFormat.languageOff('Swift');
    }
    return CodingSymbolFormat.unsupportedExtension;
  }

  Future<String> _call(Future<String> Function() run) async {
    try {
      return await run();
    } catch (e) {
      return CodingSymbolFormat.failed(e);
    }
  }
}
