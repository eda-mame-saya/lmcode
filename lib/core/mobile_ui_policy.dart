import 'package:flutter/foundation.dart';

/// スマホ（iOS / Android）向けの UI 制限。
/// 検討10 §5.1: Mac＝フル機能、iPhone＝一部非表示。
class MobileUiPolicy {
  const MobileUiPolicy._();

  static bool get isMobilePlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  /// デスクトップ（macOS / Windows）。
  static bool get isDesktopPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  /// オンライン会議リアルタイム（音声横取り）が利用可能か。
  /// macOS 実装済。Windows は Phase1（マイク＋WASAPI Loopback、仮想マイクなし）。
  static bool get supportsOnlineRealtimeCapture =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  /// リアルタイム（対面／オンライン）画面の事前圧縮ボタンを出さない。
  /// アルファ: 全プラットフォームで非表示。第N回詳細は外部AI向けプロンプト表示へ。
  static bool get hideRealtimePreCompress => true;

  /// 対面会議の「デモ会話を挿入」を出さない（アルファ）。
  static bool get hideDemoConversationInsert => true;

  /// カレンダー共有画面の「第N回フォルダを開く」を出さない。
  static bool get hideCalendarStorageOpenButtons => isMobilePlatform;

  /// ホーム「最近のプロジェクト」行の「最新の会話」を出さない。
  /// アルファ: いったん表示する（`false`）。
  static bool get hideHomeLatestConversation => true;
}
