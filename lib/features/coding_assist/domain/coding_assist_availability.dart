import 'package:flutter/foundation.dart';

/// S16 コーディングアシストの UI 提供可否。
///
/// Windows は負荷・検証状況から画面入口を出さない（S11 設定は残す）。
/// GPU 搭載 Windows への搭載は設計上の検討事項。
abstract final class CodingAssistAvailability {
  /// サイドバー入口・`/coding-assist` を有効にするか。
  static bool get isUiEnabled =>
      !kIsWeb && defaultTargetPlatform != TargetPlatform.windows;
}
