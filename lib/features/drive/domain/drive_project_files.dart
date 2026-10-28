/// プロジェクトフォルダ直下のファイル名規約。
/// 新規追加：プロジェクト参加者・単語帳は第N回ではなくプロジェクト共通
abstract final class DriveProjectFiles {
  /// プロジェクト参加者リスト。
  static const participants = 'プロジェクト参加者.json';

  /// プロジェクト共通の単語帳（会議回を跨いで共有）。意味調べ用。
  static const wordbook = '単語帳.json';

  /// プロジェクト共通の ASR 認識単語（Whisper initial_prompt 用・最大10語）。
  static const asrVocabulary = '認識単語.json';

  /// 進捗マスターリスト（スケジューリング済み ＴＯＤＯの集約表）
  static const progressMaster = '進捗マスターリスト.xlsx';

  /// Excel 進捗マスターの MIME。
  static const progressMasterMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
}
