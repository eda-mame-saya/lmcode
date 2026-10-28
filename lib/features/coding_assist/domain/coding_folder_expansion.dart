/// フォルダ操作ツリーの展開記憶。
///
/// 値が無いパスは既定展開（`lib`／`test`／`ios`／`android`）に従う。
/// 記録があるパスだけ、前回の展開／折りたたみを優先する。
final class CodingFolderExpansion {
  const CodingFolderExpansion._();

  /// `index.json` に残すワークスペース数の上限。
  static const maxRememberedWorkspaces = 32;

  /// ワークスペース相対のディレクトリ。空・絶対・`..` は記録しない。
  static String? normalizeRelative(String raw) {
    var path = raw.replaceAll('\\', '/').trim();
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    if (path.startsWith('/')) return null;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.isEmpty || path == '.') return null;
    final segments = path.split('/');
    if (segments.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
    return path;
  }

  static bool isExpanded({
    required String relativePath,
    required bool preferInitiallyExpanded,
    required Map<String, bool>? remembered,
  }) {
    if (remembered == null) return preferInitiallyExpanded;
    final key = normalizeRelative(relativePath);
    if (key == null) return preferInitiallyExpanded;
    return remembered[key] ?? preferInitiallyExpanded;
  }

  /// いま見えているフォルダの状態を、前回の記録へ重ねる。
  ///
  /// 折りたたみ中で見えていないパスは前回の値を残す。
  static Map<String, bool> merge({
    required Map<String, bool>? remembered,
    required Map<String, bool> visible,
  }) {
    final next = <String, bool>{};
    if (remembered != null) {
      for (final entry in remembered.entries) {
        final key = normalizeRelative(entry.key);
        if (key == null) continue;
        next[key] = entry.value;
      }
    }
    for (final entry in visible.entries) {
      final key = normalizeRelative(entry.key);
      if (key == null) continue;
      next[key] = entry.value;
    }
    return next;
  }

  static bool same(Map<String, bool>? a, Map<String, bool>? b) {
    final left = a ?? const <String, bool>{};
    final right = b ?? const <String, bool>{};
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// ディレクトリ移動・改名。記録が無ければ null。変化が無ければ同じ Map。
  static Map<String, bool>? movePrefix({
    required Map<String, bool>? remembered,
    required String from,
    required String to,
  }) {
    if (remembered == null) return null;
    final src = normalizeRelative(from);
    final dst = normalizeRelative(to);
    if (src == null || dst == null || src == dst) return remembered;
    final next = <String, bool>{};
    var changed = false;
    for (final entry in remembered.entries) {
      final path = normalizeRelative(entry.key);
      if (path == null) {
        changed = true;
        continue;
      }
      if (path == src || path.startsWith('$src/')) {
        next['$dst${path.substring(src.length)}'] = entry.value;
        changed = true;
      } else {
        next[path] = entry.value;
      }
    }
    if (!changed) return remembered;
    return next;
  }

  /// ディレクトリ削除。記録が無ければ null。変化が無ければ同じ Map。
  static Map<String, bool>? removePrefix({
    required Map<String, bool>? remembered,
    required String directory,
  }) {
    if (remembered == null) return null;
    final src = normalizeRelative(directory);
    if (src == null) return remembered;
    final next = <String, bool>{};
    var changed = false;
    for (final entry in remembered.entries) {
      final path = normalizeRelative(entry.key);
      if (path == null || path == src || path.startsWith('$src/')) {
        changed = true;
        continue;
      }
      next[path] = entry.value;
    }
    if (!changed) return remembered;
    return next;
  }
}
