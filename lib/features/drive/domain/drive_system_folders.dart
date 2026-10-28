/// LMCode 直下のアプリ専用フォルダ（ユーザープロジェクトではない）。
/// プロジェクト一覧・新規作成から除外する。
abstract final class DriveSystemFolders {

  /// llama-server／GGUF 展開先（設計上予約。未展開でも同名プロジェクト作成を禁止）。
  static const localLlm = 'local_llm';

  /// S16 コーディングアシスト（会話・直近ワークスペース）。
  static const codingAssist = 'coding_assist';

  /// プロジェクト／第N回未選択時の退避先（子は日時フォルダ。第N回名ではない）。
  /// [DriveUnsortedFolders.projectName] と同名であること。

  static const reservedNames = <String>{
    localLlm,
    codingAssist,
  };

  static bool isReserved(String folderName) =>
      reservedNames.contains(folderName.trim());
}
