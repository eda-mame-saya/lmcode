/// 選択した識別子の LSP definition と、吹き出しに出す抜粋。
class CodingDartDefinitionQuery {
  const CodingDartDefinitionQuery({
    required this.line,
    required this.character,
    required this.word,
  });

  final int line;
  final int character;
  final String word;
}

class CodingDartDefinitionLocation {
  const CodingDartDefinitionLocation({
    required this.uri,
    required this.startLine,
    required this.startCharacter,
    required this.endLine,
    required this.endCharacter,
  });

  final String uri;
  final int startLine;
  final int startCharacter;
  final int endLine;
  final int endCharacter;
}

class CodingDartDefinitionSnippet {
  const CodingDartDefinitionSnippet({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

/// 選択範囲が識別子ならその語、そうでなければキャレット位置の識別子。
CodingDartDefinitionQuery? codingDartSelectedIdentifier({
  required bool collapsed,
  required int baseLine,
  required int baseOffset,
  required int extentLine,
  required int extentOffset,
  required String lineText,
}) {
  if (baseLine != extentLine) return null;
  if (!collapsed) {
    final start = baseOffset < extentOffset ? baseOffset : extentOffset;
    final end = baseOffset < extentOffset ? extentOffset : baseOffset;
    if (start >= 0 && end <= lineText.length && start != end) {
      final word = lineText.substring(start, end);
      if (_identifier.hasMatch(word)) {
        return CodingDartDefinitionQuery(
          line: baseLine,
          character: start,
          word: word,
        );
      }
    }
  }
  final caret = collapsed ? baseOffset : extentOffset;
  final ident = _identifierAt(lineText, caret);
  if (ident == null) return null;
  return CodingDartDefinitionQuery(
    line: baseLine,
    character: ident.character,
    word: ident.word,
  );
}

({String word, int character})? _identifierAt(String line, int offset) {
  if (line.isEmpty || offset < 0 || offset > line.length) return null;
  var index = offset;
  if (index == line.length || !_isIdentChar(line[index])) {
    if (index == 0) return null;
    index -= 1;
  }
  if (!_isIdentChar(line[index])) return null;
  var start = index;
  while (start > 0 && _isIdentChar(line[start - 1])) {
    start--;
  }
  var end = index + 1;
  while (end < line.length && _isIdentChar(line[end])) {
    end++;
  }
  final word = line.substring(start, end);
  if (!_identifier.hasMatch(word)) return null;
  return (word: word, character: index);
}

bool _isIdentChar(String ch) {
  if (ch.length != 1) return false;
  final c = ch.codeUnitAt(0);
  return (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c == 95 ||
      c == 36;
}

/// `targetRange`（宣言全体）を優先する。名前だけの selection は使わない。
CodingDartDefinitionLocation? codingDartDefinitionLocation(Object? result) {
  final map = _firstMap(result);
  if (map == null) return null;
  final uri = map['targetUri'] ?? map['uri'];
  if (uri is! String || uri.isEmpty) return null;
  final range = map['targetRange'] ?? map['range'];
  if (range is! Map) return null;
  final start = range['start'];
  final end = range['end'];
  if (start is! Map || end is! Map) return null;
  final startLine = start['line'];
  final startCharacter = start['character'];
  final endLine = end['line'];
  final endCharacter = end['character'];
  if (startLine is! int ||
      startCharacter is! int ||
      endLine is! int ||
      endCharacter is! int) {
    return null;
  }
  return CodingDartDefinitionLocation(
    uri: uri,
    startLine: startLine,
    startCharacter: startCharacter,
    endLine: endLine,
    endCharacter: endCharacter,
  );
}

/// 宣言範囲と、その直前の `///` コメントを抜粋する。長いときは切る。
CodingDartDefinitionSnippet? codingDartDefinitionSnippet({
  required String source,
  required CodingDartDefinitionLocation location,
  required String fileLabel,
  int maxLines = 40,
}) {
  final lines = source.split('\n');
  if (location.startLine < 0 || location.startLine >= lines.length) return null;
  var start = location.startLine;
  while (start > 0) {
    final prev = lines[start - 1].trimLeft();
    if (prev.startsWith('///') ||
        prev.startsWith('//') ||
        prev.startsWith('@')) {
      start--;
      continue;
    }
    break;
  }
  var end = location.endLine;
  if (end < start) end = start;
  if (end >= lines.length) end = lines.length - 1;
  final truncated = end - start + 1 > maxLines;
  if (truncated) end = start + maxLines - 1;
  final body = [
    ...lines.sublist(start, end + 1),
    if (truncated) '…',
  ].join('\n');
  return CodingDartDefinitionSnippet(
    title: '$fileLabel:${start + 1}',
    body: body,
  );
}

/// SourceKit の定義 range は名前の先頭 1 点になる。その行に `{` があれば対応する `}` まで広げる。
CodingDartDefinitionLocation codingSwiftExpandPointDefinition({
  required CodingDartDefinitionLocation location,
  required String source,
}) {
  if (location.startLine != location.endLine ||
      location.startCharacter != location.endCharacter) {
    return location;
  }
  final end = codingSwiftDeclarationEndLine(source, location.startLine);
  if (end <= location.startLine) return location;
  return CodingDartDefinitionLocation(
    uri: location.uri,
    startLine: location.startLine,
    startCharacter: location.startCharacter,
    endLine: end,
    endCharacter: location.endCharacter,
  );
}

/// [startLine] から波括弧の対応を取り、宣言の終了行を返す。`{` が無ければ [startLine]。
int codingSwiftDeclarationEndLine(String source, int startLine) {
  final lines = source.split('\n');
  if (startLine < 0 || startLine >= lines.length) return startLine;
  var depth = 0;
  var opened = false;
  var inBlock = false;
  for (var i = startLine; i < lines.length; i++) {
    final line = lines[i];
    if (i > startLine && !opened && _looksLikeNextSwiftDeclaration(line)) {
      return startLine;
    }
    var inLineComment = false;
    var inString = false;
    var delim = '';
    for (var c = 0; c < line.length; c++) {
      final ch = line[c];
      final next = c + 1 < line.length ? line[c + 1] : '';
      if (inLineComment) break;
      if (inBlock) {
        if (ch == '*' && next == '/') {
          inBlock = false;
          c++;
        }
        continue;
      }
      if (inString) {
        if (ch == '\\') {
          c++;
          continue;
        }
        if (ch == delim) inString = false;
        continue;
      }
      if (ch == '/' && next == '/') {
        inLineComment = true;
        break;
      }
      if (ch == '/' && next == '*') {
        inBlock = true;
        c++;
        continue;
      }
      if (ch == '"' || ch == "'") {
        inString = true;
        delim = ch;
        continue;
      }
      if (ch == '{') {
        depth++;
        opened = true;
      } else if (ch == '}') {
        if (depth > 0) depth--;
        if (opened && depth == 0) return i;
      }
    }
  }
  return opened ? lines.length - 1 : startLine;
}

bool _looksLikeNextSwiftDeclaration(String line) {
  final trimmed = line.trimLeft();
  const prefixes = [
    'func ',
    'var ',
    'let ',
    'public ',
    'private ',
    'internal ',
    'open ',
    'struct ',
    'class ',
    'enum ',
    'protocol ',
    'extension ',
    'init',
    '@',
  ];
  for (final prefix in prefixes) {
    if (trimmed.startsWith(prefix)) return true;
  }
  return false;
}

Map? _firstMap(Object? result) {
  if (result is List) {
    for (final item in result) {
      final map = _firstMap(item);
      if (map != null) return map;
    }
    return null;
  }
  if (result is Map) return result;
  return null;
}
