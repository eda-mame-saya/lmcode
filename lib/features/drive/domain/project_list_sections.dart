import 'entities/drive_project.dart';

/// S02 のセクション分割結果。
final class ProjectListSections {
  const ProjectListSections({
    required this.recent,
    required this.favorites,
    required this.others,
  });

  final List<DriveProject> recent;
  final List<DriveProject> favorites;
  final List<DriveProject> others;

  /// 「最近 → お気に入り → 他」に振り分ける。各プロジェクトは1セクションのみ。
  ///
  /// お気に入り（星 ON）は **すべて「お気に入り」へ**置く（最近枠より優先）。
  /// 最近はお気に入り以外からアクセス順最大 [recentLimit] 件。
  static ProjectListSections partition({
    required List<DriveProject> projects,
    required Set<String> favoriteNames,
    required Map<String, DateTime> lastAccess,
    int recentLimit = 5,
  }) {
    final favorites = projects
        .where((p) => favoriteNames.contains(p.displayName))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final favoriteIds = favorites.map((p) => p.id).toSet();

    final nonFavorites =
        projects.where((p) => !favoriteIds.contains(p.id)).toList();
    final sortedNonFavorites = [...nonFavorites]..sort((a, b) {
        final ta = lastAccess[a.displayName];
        final tb = lastAccess[b.displayName];
        if (ta != null || tb != null) {
          if (ta == null) return 1;
          if (tb == null) return -1;
          final byAccess = tb.compareTo(ta);
          if (byAccess != 0) return byAccess;
        }
        final ua = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final ub = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final byUpdated = ub.compareTo(ua);
        if (byUpdated != 0) return byUpdated;
        return a.displayName.compareTo(b.displayName);
      });

    final recent = sortedNonFavorites.take(recentLimit).toList(growable: false);
    final recentIds = recent.map((p) => p.id).toSet();
    final others = nonFavorites
        .where((p) => !recentIds.contains(p.id))
        .toList()
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return ProjectListSections(
      recent: recent,
      favorites: favorites,
      others: others,
    );
  }
}

/// 一覧用の日時表示（例: 2026年10月5日 12:24:34）。
String formatProjectDateTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  final y = local.year;
  final m = local.month;
  final d = local.day;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  final ss = local.second.toString().padLeft(2, '0');
  return '$y年$m月$d日 $hh:$mm:$ss';
}
