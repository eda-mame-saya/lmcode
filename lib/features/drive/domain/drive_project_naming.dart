import 'drive_system_folders.dart';

/// Drive 上のプロジェクトフォルダ名の規約（非表示判定）。
abstract final class DriveProjectNaming {
  /// 非表示プロジェクトの Drive フォルダ接頭辞。
  static const hiddenPrefix = '非表示_';

  static bool isHidden(String folderName) =>
      folderName.startsWith(hiddenPrefix);

  /// 一覧表示用の名称（接頭辞を除く）。
  static String displayName(String folderName) {
    if (!isHidden(folderName)) return folderName;
    final withoutPrefix = folderName.substring(hiddenPrefix.length);
    return withoutPrefix.isEmpty ? folderName : withoutPrefix;
  }

  /// 非表示用の Drive フォルダ名へ変換する。
  static String toHiddenFolderName(String folderName) {
    if (isHidden(folderName)) return folderName;
    return '$hiddenPrefix$folderName';
  }

  /// 表示用の Drive フォルダ名へ戻す。
  static String toVisibleFolderName(String folderName) {
    if (!isHidden(folderName)) return folderName;
    final visible = folderName.substring(hiddenPrefix.length);
    if (visible.isEmpty) {
      throw FormatException('非表示接頭辞のみのフォルダ名は復元できません: $folderName');
    }
    return visible;
  }

  /// 新規作成時にユーザーが付けた名称として許可するか。
  static bool isAllowedNewProjectName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return false;
    if (isHidden(trimmed)) return false;
    if (DriveSystemFolders.isReserved(trimmed)) return false;
    return true;
  }

  /// 表示名から Drive フォルダ名を組み立てる（非表示状態を維持）。
  static String folderNameForDisplayName({
    required String displayName,
    required bool keepHidden,
  }) {
    final trimmed = displayName.trim();
    if (!isAllowedNewProjectName(trimmed)) {
      if (trimmed.isEmpty) {
        throw FormatException('プロジェクト名を入力してください。');
      }
      if (DriveSystemFolders.isReserved(trimmed)) {
        throw FormatException('「$trimmed」はシステム用のためプロジェクト名に使えません。');
      }
      throw FormatException(
        'プロジェクト名に「$hiddenPrefix」は使えません。',
      );
    }
    return keepHidden ? toHiddenFolderName(trimmed) : trimmed;
  }
}
