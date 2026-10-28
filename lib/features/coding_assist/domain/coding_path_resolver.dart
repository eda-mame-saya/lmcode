import 'package:path/path.dart' as p;

/// Agent ツール向けパス正規化・候補解決（S16）。
abstract final class CodingPathResolver {
  static const maxCandidates = 8;

  /// LLM が付けがちな装飾・WS 名付き・絶対パスを相対パスへ寄せる。
  static String normalizeInput(
    String raw, {
    required String rootPath,
    String? rootLabel,
    List<String> indexedFiles = const [],
    List<String> indexedDirectories = const [],
  }) {
    var s = raw.trim();
    if (s.isEmpty) return '';

    s = s.replaceAll('`', '').replaceAll('"', '').replaceAll("'", '');
    s = s.replaceAll('\\', '/');
    while (s.startsWith('./')) {
      s = s.substring(2);
    }
    if (s.endsWith('/') && s.length > 1) {
      s = s.substring(0, s.length - 1);
    }

    final rootNorm = p.normalize(rootPath).replaceAll('\\', '/');
    if (p.isAbsolute(s)) {
      final abs = p.normalize(s).replaceAll('\\', '/');
      final rootCmp = rootNorm.toLowerCase();
      final absCmp = abs.toLowerCase();
      if (absCmp == rootCmp) return '';
      if (absCmp.startsWith('$rootCmp/')) {
        s = abs.substring(rootNorm.length + 1);
      }
    }

    final labels = <String>{
      if (rootLabel != null && rootLabel.trim().isNotEmpty)
        rootLabel.trim().replaceAll('\\', '/'),
      p.basename(rootNorm),
    };
    for (final label in labels) {
      if (label.isEmpty) continue;
      if (s == label) return '';
      if (s.startsWith('$label/')) {
        final rest = s.substring(label.length + 1);
        if (_workspaceLabelIsRedundantPrefix(
          label: label,
          remainder: rest,
          indexedFiles: indexedFiles,
          indexedDirectories: indexedDirectories,
        )) {
          s = rest;
        }
        break;
      }
    }

    final normalized = p.normalize(s).replaceAll('\\', '/');
    if (normalized == '.' || normalized == './') return '';
    return normalized;
  }

  /// 先頭がワークスペース名でも、中の実ディレクトリやファイル名だけになる新規パスは残す。
  ///
  /// Xcode は `MyApp/ContentView.swift` のように、開いたフォルダと同じ名前の
  /// ディレクトリをソースの置き場にする。ここを落とすと作成カードがファイル名だけになる。
  /// `my_app/lib/main.dart` のように残りが別ディレクトリなら、従来どおり落とす。
  static bool _workspaceLabelIsRedundantPrefix({
    required String label,
    required String remainder,
    required List<String> indexedFiles,
    required List<String> indexedDirectories,
  }) {
    final rest = remainder.replaceAll('\\', '/');
    if (rest.isEmpty || rest == '.') return true;
    final files = [
      for (final file in indexedFiles)
        if (file.replaceAll('\\', '/').isNotEmpty) file.replaceAll('\\', '/'),
    ];
    final dirs = [
      for (final dir in indexedDirectories)
        if (dir.replaceAll('\\', '/').isNotEmpty) dir.replaceAll('\\', '/'),
    ];
    if (files.contains(rest) || dirs.contains(rest)) return true;
    final prefix = '$label/';
    final labelIsInside =
        dirs.contains(label) ||
        dirs.any((dir) => dir.startsWith(prefix)) ||
        files.any((file) => file.startsWith(prefix));
    if (labelIsInside) return false;
    return rest.contains('/');
  }

  /// 索引上のファイルに対するソフト一致（厳密 → 大小無視 → basename 一意）。
  static String? softMatchFile(
    String normalizedRelative,
    List<String> indexedFiles,
  ) {
    if (normalizedRelative.isEmpty) return null;
    final files = indexedFiles
        .map((e) => e.replaceAll('\\', '/'))
        .where((e) => e.isNotEmpty)
        .toList();
    for (final f in files) {
      if (f == normalizedRelative) return f;
    }
    final lower = normalizedRelative.toLowerCase();
    String? ci;
    for (final f in files) {
      if (f.toLowerCase() == lower) {
        if (ci != null && ci != f) return null;
        ci = f;
      }
    }
    if (ci != null) return ci;

    final base = p.basename(normalizedRelative).toLowerCase();
    if (base.isEmpty || base == '.' || base == '..') return null;
    final byBase = <String>[];
    for (final f in files) {
      if (p.basename(f).toLowerCase() == base) byBase.add(f);
    }
    if (byBase.length == 1) return byBase.first;
    return null;
  }

  /// ディレクトリのソフト一致（索引 dirs ＋ファイル親パス）。
  static String? softMatchDir(
    String normalizedRelative,
    List<String> indexedDirs,
    List<String> indexedFiles,
  ) {
    if (normalizedRelative.isEmpty) return '';
    final dirs = <String>{
      for (final d in indexedDirs)
        if (d.replaceAll('\\', '/').isNotEmpty) d.replaceAll('\\', '/'),
    };
    for (final f in indexedFiles) {
      final rel = f.replaceAll('\\', '/');
      var parent = p.dirname(rel).replaceAll('\\', '/');
      while (parent.isNotEmpty && parent != '.') {
        dirs.add(parent);
        final next = p.dirname(parent).replaceAll('\\', '/');
        if (next == parent) break;
        parent = next;
      }
    }
    if (dirs.contains(normalizedRelative)) return normalizedRelative;
    final lower = normalizedRelative.toLowerCase();
    String? ci;
    for (final d in dirs) {
      if (d.toLowerCase() == lower) {
        if (ci != null && ci != d) return null;
        ci = d;
      }
    }
    if (ci != null) return ci;

    final base = p.basename(normalizedRelative).toLowerCase();
    final byBase = dirs
        .where((d) => p.basename(d).toLowerCase() == base)
        .toList();
    if (byBase.length == 1) return byBase.first;
    return null;
  }

  /// 見つからないときの候補（basename・部分一致優先）。
  static List<String> suggestCandidates({
    required String query,
    required List<String> indexedFiles,
    List<String> indexedDirs = const [],
    int limit = maxCandidates,
  }) {
    final q = query.replaceAll('\\', '/').trim();
    if (q.isEmpty || limit <= 0) return const [];
    final qLower = q.toLowerCase();
    final qBase = p.basename(q).toLowerCase();
    final qDir = p.dirname(q).replaceAll('\\', '/').toLowerCase();
    final qStem = qBase.contains('.')
        ? qBase.substring(0, qBase.lastIndexOf('.'))
        : qBase;

    final scored = <({String path, int score})>[];
    void consider(String path, {required bool isDir}) {
      final rel = path.replaceAll('\\', '/');
      if (rel.isEmpty) return;
      final lower = rel.toLowerCase();
      final base = p.basename(rel).toLowerCase();
      final stem = base.contains('.')
          ? base.substring(0, base.lastIndexOf('.'))
          : base;
      var score = 0;
      if (lower == qLower) {
        score = 1000;
      } else if (base == qBase && qBase.isNotEmpty) {
        score = 800 - (rel.length - base.length).clamp(0, 200);
      } else if (qBase.length >= 2 && base.contains(qBase)) {
        score = 500 - (base.length - qBase.length).clamp(0, 100);
      } else if (qStem.length >= 3 &&
          qStem != qBase &&
          (stem.contains(qStem) || qStem.contains(stem))) {
        // login_view ↔ login_page など
        score = 420;
      } else if (qLower.length >= 3 && lower.contains(qLower)) {
        score = 300;
      } else if (qDir.isNotEmpty &&
          qDir != '.' &&
          qDir.length >= 3 &&
          lower.contains(qDir)) {
        // 同じ親フォルダ配下を候補に（features/login/foo.dart → login_page.dart）
        score = 260;
      } else if (qBase.length >= 3 && lower.contains(qBase)) {
        score = 200;
      } else {
        return;
      }
      if (isDir) score -= 5;
      scored.add((path: isDir ? '$rel/' : rel, score: score));
    }

    for (final f in indexedFiles) {
      consider(f, isDir: false);
    }
    for (final d in indexedDirs) {
      consider(d, isDir: true);
    }

    scored.sort((a, b) {
      final c = b.score.compareTo(a.score);
      if (c != 0) return c;
      return a.path.compareTo(b.path);
    });

    final out = <String>[];
    final seen = <String>{};
    for (final s in scored) {
      final key = s.path.toLowerCase();
      if (!seen.add(key)) continue;
      out.add(s.path);
      if (out.length >= limit) break;
    }
    return out;
  }

  static String formatNotFound({
    required String kind,
    required String requested,
    required List<String> candidates,
  }) {
    final buf = StringBuffer('$kindがありません: $requested');
    if (candidates.isNotEmpty) {
      buf.writeln();
      buf.writeln('候補:');
      for (final c in candidates) {
        buf.writeln('- $c');
      }
      buf.write('（どれかをツールで指定し直してください）');
    }
    return buf.toString();
  }
}
