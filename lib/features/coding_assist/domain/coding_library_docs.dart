// 版付きライブラリ docs 取得（Agent tool `fetch_library_docs`）の共有定数・整形。

/// tool 結果の本文上限（呼び出し側の clip 前の目安）。
const codingLibraryDocsMaxChars = 12000;

/// 1 チャンクの目安。
const codingLibraryDocsChunkChars = 1800;

/// system に足す説明。ローカル LSP／キャッシュ優先。
const codingLibraryDocsToolPromptBuiltIn = '''
版付きライブラリ docs（ネット可。ローカル優先）:
```tool
{"name":"fetch_library_docs","args":{"library":"http","query":"Client get timeout"}}
```
任意引数: `"version":"1.2.2"`（省略時は lock／package_config から解決）、`"ecosystem":"dart"|"npm"|"pypi"|"auto"`（既定 auto）。
- シグネチャや定義の事実は、先に hover / go_to_definition（またはローカル依存の実体）を使う
- fetch_library_docs は公式 README／CHANGELOG／例など**説明・使い方**の補強。ローカルで足りるときは呼ばない
- 送信してよいのはライブラリ名・版・短い query のみ（ソース全文は送らない）
- 失敗してもローカル調査で続行する
''';

/// [raw] を query に関連する抜粋へ縮める。
String codingLibraryDocsSelectPassages({
  required String raw,
  required String query,
  int maxChars = codingLibraryDocsMaxChars,
  int chunkChars = codingLibraryDocsChunkChars,
}) {
  final text = raw.trim();
  if (text.isEmpty) return '';
  if (text.length <= maxChars) return text;

  final tokens = _queryTokens(query);
  final blocks = _splitBlocks(text);
  if (blocks.isEmpty) {
    return text.length <= maxChars ? text : '${text.substring(0, maxChars)}\n…';
  }

  final scored = <({int score, int index, String body})>[
    for (var i = 0; i < blocks.length; i++)
      (score: _scoreBlock(blocks[i], tokens), index: i, body: blocks[i]),
  ]..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.index.compareTo(b.index);
    });

  final picked = <({int index, String body})>[];
  var used = 0;
  for (final item in scored) {
    if (item.score <= 0 && picked.isNotEmpty) break;
    var body = item.body.trim();
    if (body.isEmpty) continue;
    if (body.length > chunkChars) {
      body = '${body.substring(0, chunkChars)}\n…';
    }
    if (used + body.length + 2 > maxChars) {
      if (picked.isEmpty) {
        picked.add((index: item.index, body: body.substring(0, maxChars)));
      }
      break;
    }
    picked.add((index: item.index, body: body));
    used += body.length + 2;
  }

  if (picked.isEmpty) {
    return text.length <= maxChars ? text : '${text.substring(0, maxChars)}\n…';
  }
  picked.sort((a, b) => a.index.compareTo(b.index));
  return picked.map((e) => e.body).join('\n\n');
}

String codingLibraryDocsFormatResult({
  required String library,
  required String version,
  required String ecosystem,
  required String source,
  required String sourceUrl,
  required String body,
  required String query,
}) {
  final buf = StringBuffer()
    ..writeln('library: $library')
    ..writeln('version: ${version.isEmpty ? '(unknown)' : version}')
    ..writeln('ecosystem: $ecosystem')
    ..writeln('source: $source')
    ..writeln('url: ${sourceUrl.isEmpty ? '(local)' : sourceUrl}')
    ..writeln('query: ${query.trim().isEmpty ? '(none)' : query.trim()}')
    ..writeln('---')
    ..write(body.trim());
  return buf.toString();
}

List<String> _queryTokens(String query) {
  final raw = query.toLowerCase().split(RegExp(r'[^a-z0-9_\.\+\-]+'));
  return [
    for (final t in raw)
      if (t.length >= 2) t,
  ];
}

List<String> _splitBlocks(String text) {
  final parts = text.split(RegExp(r'\n{2,}'));
  final out = <String>[];
  final buf = StringBuffer();
  for (final part in parts) {
    final p = part.trim();
    if (p.isEmpty) continue;
    if (buf.isEmpty) {
      buf.write(p);
      continue;
    }
    if (buf.length + p.length + 2 <= codingLibraryDocsChunkChars) {
      buf
        ..writeln()
        ..writeln()
        ..write(p);
    } else {
      out.add(buf.toString());
      buf
        ..clear()
        ..write(p);
    }
  }
  if (buf.isNotEmpty) out.add(buf.toString());
  return out;
}

int _scoreBlock(String block, List<String> tokens) {
  if (tokens.isEmpty) return 1;
  final lower = block.toLowerCase();
  var score = 0;
  for (final t in tokens) {
    if (lower.contains(t)) score += 2;
  }
  if (block.startsWith('#')) score += 1;
  if (block.contains('```')) score += 1;
  return score;
}
