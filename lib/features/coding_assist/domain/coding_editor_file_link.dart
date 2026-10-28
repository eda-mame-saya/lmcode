/// Agent が「このファイルを開いて」と出す Markdown リンク。
/// 形式: `[lib/foo.dart](coding-file:lib/foo.dart)`
const codingFileLinkPrefix = 'coding-file:';

/// `coding-file:` のワークスペース相対パスだけを返す。開けない href は null。
String? codingAssistEditorLinkPath(String? href) {
  if (href == null) return null;
  var raw = href.trim();
  if (raw.isEmpty) return null;
  try {
    raw = Uri.decodeFull(raw);
  } catch (_) {
    return null;
  }
  if (!raw.startsWith(codingFileLinkPrefix)) return null;
  var path = raw.substring(codingFileLinkPrefix.length).trim();
  path = path.replaceAll('\\', '/');
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  if (path.isEmpty || path.startsWith('/')) return null;
  if (path.contains(':')) return null;
  final parts = path.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  return path;
}
