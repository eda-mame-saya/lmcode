/// プロジェクト未選択時の退避保存先（LMCode 直下）。
/// 新規追加：検討10 §3.2 / §3.7
abstract final class DriveUnsortedFolders {
  /// LMCode 直下の退避プロジェクト名。
  static const projectName = '未整理フォルダ';

  /// `YYYY_MM_DD_hh_mm_ss`（例: 2026_09_29_11_26_05）。衝突時の接尾辞 `_2` 等も許容。
  static final RegExp captureFolderPattern = RegExp(
    r'^(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})(?:_.+)?$',
  );

  static bool isCaptureFolderName(String folderName) =>
      captureFolderPattern.hasMatch(folderName.trim());

  static String captureFolderName(DateTime at) {
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${at.year}_${p2(at.month)}_${p2(at.day)}_'
        '${p2(at.hour)}_${p2(at.minute)}_${p2(at.second)}';
  }
}
