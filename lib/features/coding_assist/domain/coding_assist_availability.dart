import 'package:flutter/foundation.dart';

/// S16 コーディングアシストの UI 提供可否。
///
/// デスクトップ（macOS／Windows）で有効。Web は対象外。
/// Swift／SourceKit-LSP は macOS のみ（Windows では起動しない）。
abstract final class CodingAssistAvailability {
  /// サイドバー入口・`/coding-assist` を有効にするか。
  static bool get isUiEnabled => !kIsWeb;
}
