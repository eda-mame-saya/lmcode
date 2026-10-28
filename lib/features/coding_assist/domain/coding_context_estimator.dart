import 'entities/coding_assist_entities.dart';

/// S16 コンテキスト使用見込み（§5.7）。しきい値はコーディング用。
abstract final class CodingContextEstimator {
  /// 日本語寄り: おおよそ 2 文字 ≒ 1 トークン。
  static const charsPerToken = 2.0;

  static const warnRatio = 0.70;
  static const autoCompactRatio = 0.85;
  static const blockRatio = 0.90;

  static int estimateTokens(
    String text, {
    double charsPerToken = CodingContextEstimator.charsPerToken,
  }) {
    if (text.isEmpty || charsPerToken <= 0) return 0;
    return (text.length / charsPerToken).ceil();
  }

  static CodingContextWarningLevel levelFor({
    required int usedTokens,
    required int contextSize,
    double? warnRatio,
    double? blockRatio,
  }) {
    if (contextSize <= 0) return CodingContextWarningLevel.none;
    final warn = warnRatio ?? CodingContextEstimator.warnRatio;
    final block = blockRatio ?? CodingContextEstimator.blockRatio;
    final ratio = usedTokens / contextSize;
    if (ratio >= block) return CodingContextWarningLevel.block;
    if (ratio >= warn) return CodingContextWarningLevel.warn;
    return CodingContextWarningLevel.none;
  }

  static bool shouldAutoCompact({
    required int usedTokens,
    required int contextSize,
    double? autoCompactRatio,
  }) {
    if (contextSize <= 0) return false;
    final compact = autoCompactRatio ?? CodingContextEstimator.autoCompactRatio;
    return usedTokens / contextSize >= compact;
  }
}
