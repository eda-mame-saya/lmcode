import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

/// LSP のシンボル結果を、Agent の窓に載せる短いテキストへ切る。
abstract final class CodingSymbolFormat {
  static const maxHits = 40;
  static const maxOutlineEntries = 80;
  static const maxDefinitionLocations = 8;
  static const maxSignatureMapChars = 2000;
  static const maxLineChars = 160;

  static const unavailable =
      'シンボル探索はオフです。list_dir / read_file / grep を使ってください。';

  static String failed(Object error) =>
      'シンボル探索に失敗しました（$error）。list_dir / read_file / grep を使ってください。';

  static String languageOff(String language) =>
      '$language のシンボル探索はオフです。list_dir / read_file / grep を使ってください。';

  static const unsupportedExtension =
      'この拡張子はシンボル探索の対象外です。read_file / grep を使ってください。';

  static String kindLabel(int kind) => switch (kind) {
        5 => 'class',
        6 => 'method',
        7 => 'property',
        8 => 'field',
        9 => 'constructor',
        10 => 'enum',
        11 => 'interface',
        12 => 'function',
        13 => 'variable',
        14 => 'constant',
        22 => 'enumMember',
        23 => 'struct',
        26 => 'typeParam',
        _ => 'symbol',
      };

  /// 1 始まりの行・列、またはその行上の識別子から LSP の 0 始まり位置を決める。
  ///
  /// 言語サーバの range 先頭がドキュメントコメントになることがあるので、
  /// [symbol] がその行に無いときは続く数行も見る。
  static ({int line, int character})? resolvePosition({
    required String text,
    required int line,
    int? column,
    String? symbol,
  }) {
    final lines = text.split('\n');
    if (line < 1 || line > lines.length) return null;
    final name = bareSymbol(symbol);
    if (column != null && column >= 1) {
      final row = lines[line - 1];
      if (column <= row.length + 1 &&
          (name == null || row.contains(name))) {
        return (line: line - 1, character: column - 1);
      }
    }
    if (name == null) return null;
    final needle = RegExp('\\b${RegExp.escape(name)}\\b');
    final last = math.min(lines.length, line + 15);
    for (var i = line - 1; i < last; i++) {
      final match = needle.firstMatch(lines[i]);
      if (match == null) continue;
      return (line: i, character: match.start);
    }
    return null;
  }

  /// `Foo.bar(…)` や `bar()` から識別子だけ取る。
  static String? bareSymbol(String? symbol) {
    var s = symbol?.trim() ?? '';
    if (s.isEmpty) return null;
    final paren = s.indexOf('(');
    if (paren > 0) s = s.substring(0, paren);
    final dot = s.lastIndexOf('.');
    if (dot >= 0 && dot < s.length - 1) s = s.substring(dot + 1);
    s = s.trim();
    if (s.isEmpty) return null;
    return s;
  }

  static List<CodingOutlineEntry> parseOutline(Object? result) {
    final out = <CodingOutlineEntry>[];
    void walk(Object? node, int depth, String? container) {
      if (node is List) {
        for (final item in node) {
          walk(item, depth, container);
        }
        return;
      }
      if (node is! Map) return;
      final name = '${node['name'] ?? ''}'.trim();
      final kind = node['kind'] is int ? node['kind'] as int : 0;
      final detailRaw = node['detail'];
      final detail = detailRaw is String ? detailRaw.trim() : null;
      final ownContainer = node['containerName'];
      final parent = ownContainer is String && ownContainer.trim().isNotEmpty
          ? ownContainer.trim()
          : container;
      final line = _lineOf(node);
      if (name.isNotEmpty && line != null) {
        out.add(
          CodingOutlineEntry(
            name: name,
            kind: kind,
            line: line + 1,
            depth: depth,
            detail: detail,
            container: parent,
          ),
        );
      }
      final children = node['children'];
      if (children is List) {
        final next = name.isEmpty ? parent : name;
        for (final child in children) {
          walk(child, depth + 1, next);
        }
      }
    }

    walk(result, 0, null);
    return out;
  }

  static List<CodingRawSymbolLocation> parseLocations(Object? result) {
    final out = <CodingRawSymbolLocation>[];
    void walk(Object? node) {
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
        return;
      }
      if (node is! Map) return;
      final nested = node['location'];
      if (nested is Map && node['uri'] == null && node['targetUri'] == null) {
        final uri = nested['targetUri'] ?? nested['uri'];
        final range = nested['targetSelectionRange'] ??
            nested['selectionRange'] ??
            nested['targetRange'] ??
            nested['range'];
        _addLocation(out, node, uri, range);
        return;
      }
      final uri = node['targetUri'] ?? node['uri'];
      final range = node['targetSelectionRange'] ??
          node['selectionRange'] ??
          node['targetRange'] ??
          node['range'];
      _addLocation(out, node, uri, range);
    }

    walk(result);
    return out;
  }

  static void _addLocation(
    List<CodingRawSymbolLocation> out,
    Map node,
    Object? uri,
    Object? range,
  ) {
    if (uri is! String || uri.isEmpty) return;
    final line = _startLine(range);
    if (line == null) return;
    final name = node['name'];
    final kind = node['kind'];
    final container = node['containerName'];
    out.add(
      CodingRawSymbolLocation(
        uri: uri,
        line: line,
        character: _startCharacter(range) ?? 0,
        name: name is String ? name.trim() : null,
        kind: kind is int ? kind : null,
        container: container is String ? container.trim() : null,
      ),
    );
  }

  static String formatOutline(
    String relativePath,
    List<CodingOutlineEntry> entries, {
    int? maxEntries,
    int? maxLineChars,
  }) {
    if (entries.isEmpty) return '$relativePath\nシンボルがありません';
    final cap = maxEntries ?? CodingSymbolFormat.maxOutlineEntries;
    final lineCap = maxLineChars ?? CodingSymbolFormat.maxLineChars;
    final lines = <String>[relativePath];
    final take = math.min(entries.length, cap);
    for (var i = 0; i < take; i++) {
      final e = entries[i];
      final indent = '  ' * e.depth.clamp(0, 6);
      final detail = e.detail?.replaceAll(RegExp(r'\s+'), ' ').trim();
      final extra = (detail != null && detail.isNotEmpty && detail != e.name)
          ? ' — ${_clipLine(detail, lineCap)}'
          : '';
      lines.add(
        '$indent L${e.line} ${kindLabel(e.kind)} ${e.name}$extra',
      );
    }
    if (entries.length > cap) {
      lines.add('…（上限 $cap）');
    }
    return lines.join('\n');
  }

  static String formatWorkspaceHits(
    List<CodingSymbolViewHit> hits, {
    int maxHits = CodingSymbolFormat.maxHits,
  }) {
    if (hits.isEmpty) return '';
    final take = math.min(hits.length, maxHits);
    final lines = <String>[];
    for (var i = 0; i < take; i++) {
      final h = hits[i];
      final who = (h.container != null && h.container!.isNotEmpty)
          ? '${h.container}.${h.name ?? ''}'
          : (h.name ?? '');
      final kind = h.kind == null ? '' : '${kindLabel(h.kind!)} ';
      final label = who.isEmpty ? kind.trim() : '$kind$who'.trim();
      lines.add(
        label.isEmpty ? '${h.path}:${h.line}' : '${h.path}:${h.line} $label',
      );
    }
    if (hits.length > maxHits) lines.add('…（上限 $maxHits）');
    return lines.join('\n');
  }

  static String formatLocated({
    required List<CodingSymbolViewHit> hits,
    required Map<String, String> sourceByPath,
    required String heading,
    int maxHits = CodingSymbolFormat.maxHits,
    int? maxLineChars,
  }) {
    if (hits.isEmpty) return '';
    final take = math.min(hits.length, maxHits);
    final blocks = <String>[];
    for (var i = 0; i < take; i++) {
      final h = hits[i];
      final head = heading.isEmpty
          ? '${h.path}:${h.line}'
          : '$heading ${h.path}:${h.line}';
      final source = sourceByPath[h.path];
      if (source == null) {
        blocks.add(head);
        continue;
      }
      final body = contextBlock(source, h.line, maxLineChars: maxLineChars);
      blocks.add(body.isEmpty ? head : '$head\n$body');
    }
    final more = hits.length > maxHits ? '\n…（上限 $maxHits）' : '';
    return '${blocks.join('\n\n')}$more';
  }

  /// ヒット行と前後1行。ヒット行は `>`。
  static String contextBlock(String source, int line, {int? maxLineChars}) {
    final lines = source.split('\n');
    if (line < 1 || line > lines.length) return '';
    final start = math.max(1, line - 1);
    final end = math.min(lines.length, line + 1);
    final buf = StringBuffer();
    for (var n = start; n <= end; n++) {
      final mark = n == line ? '>' : ' ';
      buf.writeln(
        '$mark${n.toString().padLeft(4)}| ${_clipLine(lines[n - 1], maxLineChars)}',
      );
    }
    return buf.toString().trimRight();
  }

  static String clip(String text, int maxChars) {
    final trimmed = text.trim();
    if (trimmed.length <= maxChars) return trimmed;
    return '${trimmed.substring(0, maxChars)}\n…';
  }

  static String? filePathFromUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'file') return null;
    try {
      return parsed.toFilePath(windows: Platform.isWindows);
    } catch (_) {
      return null;
    }
  }

  static String displayPath(String absoluteOrUri, String root) {
    final abs = absoluteOrUri.startsWith('file:')
        ? (filePathFromUri(absoluteOrUri) ?? absoluteOrUri)
        : absoluteOrUri;
    final normAbs = p.normalize(abs);
    final normRoot = p.normalize(root);
    if (normAbs == normRoot || p.isWithin(normRoot, normAbs)) {
      final rel = p.relative(normAbs, from: normRoot).replaceAll('\\', '/');
      return rel.isEmpty ? '.' : rel;
    }
    return normAbs;
  }

  static String _clipLine(String line, [int? maxChars]) {
    final cap = maxChars ?? maxLineChars;
    final flat = line.replaceAll('\t', '  ');
    if (flat.length <= cap) return flat;
    return '${flat.substring(0, cap)}…';
  }

  static int? _lineOf(Map node) {
    final range = node['selectionRange'] ?? node['range'];
    return _startLine(range);
  }

  static int? _startLine(Object? range) {
    if (range is! Map) return null;
    final start = range['start'];
    if (start is! Map) return null;
    final line = start['line'];
    if (line is int) return line;
    if (line is num) return line.toInt();
    return null;
  }

  static int? _startCharacter(Object? range) {
    if (range is! Map) return null;
    final start = range['start'];
    if (start is! Map) return null;
    final character = start['character'];
    if (character is int) return character;
    if (character is num) return character.toInt();
    return null;
  }
}

class CodingOutlineEntry {
  const CodingOutlineEntry({
    required this.name,
    required this.kind,
    required this.line,
    required this.depth,
    this.detail,
    this.container,
  });

  final String name;
  final int kind;
  final int line;
  final int depth;
  final String? detail;
  final String? container;
}

class CodingRawSymbolLocation {
  const CodingRawSymbolLocation({
    required this.uri,
    required this.line,
    required this.character,
    this.name,
    this.kind,
    this.container,
  });

  final String uri;
  final int line;
  final int character;
  final String? name;
  final int? kind;
  final String? container;
}

class CodingSymbolViewHit {
  const CodingSymbolViewHit({
    required this.path,
    required this.line,
    this.name,
    this.kind,
    this.container,
  });

  final String path;
  final int line;
  final String? name;
  final int? kind;
  final String? container;
}
