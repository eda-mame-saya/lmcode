/// 第N回フォルダ名の規約（端末ラベル・取込別名対応）。
/// 新規追加：検討10 §5.1
abstract final class DriveSessionNaming {
  /// `第01回` または `第01回_ラベル`（ラベルに `_取込N` を含みうる）。
  static final RegExp namePattern = RegExp(r'^第(\d{2})回(?:_(.+))?$');

  /// フォルダ名から回番号を取る。非対応形式は null。
  static int? extractIndex(String folderName) {
    final matched = namePattern.firstMatch(folderName.trim());
    if (matched == null) return null;
    return int.tryParse(matched.group(1) ?? '');
  }

  /// 一覧に含める第N回フォルダか。
  static bool isSessionFolderName(String folderName) =>
      extractIndex(folderName) != null;

  /// 新規作成用のフォルダ名。
  static String folderName({
    required int sessionIndex,
    String deviceLabel = '',
  }) {
    final base = '第${sessionIndex.toString().padLeft(2, '0')}回';
    final label = _sanitizeLabel(deviceLabel);
    if (label.isEmpty) return base;
    return '${base}_$label';
  }

  /// 同名衝突時の別名（`元名_取込N`）。
  static String nextImportAlias({
    required String originalName,
    required Set<String> existingNames,
  }) {
    var n = 1;
    while (true) {
      final candidate = '${originalName}_取込$n';
      if (!existingNames.contains(candidate)) return candidate;
      n++;
    }
  }

  static String _sanitizeLabel(String raw) {
    return raw
        .trim()
        .replaceAll(RegExp(r'[/\\]'), '_')
        .replaceAll(RegExp(r'\s+'), '');
  }
}
