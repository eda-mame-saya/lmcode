/// ⌘N で作る拡張子なしの仮ファイル名。
///
/// 同階層の `Untitled-1` から空き番号を使う。`Untitled.txt` や別階層は数えない。
String codingAssistNextUntitledName({
  required Iterable<String> relativePaths,
  String parentRelativeDir = '',
}) {
  final parent = _untitledParent(parentRelativeDir);
  final used = <int>{};
  final numbered = RegExp(r'^Untitled-(\d+)$');
  for (final raw in relativePaths) {
    final rel = raw.replaceAll('\\', '/').trim();
    if (rel.isEmpty) continue;
    final String name;
    if (parent.isEmpty) {
      if (rel.contains('/')) continue;
      name = rel;
    } else {
      final prefix = '$parent/';
      if (!rel.startsWith(prefix)) continue;
      final rest = rel.substring(prefix.length);
      if (rest.isEmpty || rest.contains('/')) continue;
      name = rest;
    }
    final match = numbered.firstMatch(name);
    if (match == null) continue;
    final n = int.tryParse(match.group(1)!);
    if (n != null && n > 0) used.add(n);
  }
  var n = 1;
  while (used.contains(n)) {
    n++;
  }
  return 'Untitled-$n';
}

String _untitledParent(String raw) {
  var path = raw.replaceAll('\\', '/').trim();
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  if (path.endsWith('/')) path = path.substring(0, path.length - 1);
  if (path == '.' || path == '/') return '';
  return path;
}
