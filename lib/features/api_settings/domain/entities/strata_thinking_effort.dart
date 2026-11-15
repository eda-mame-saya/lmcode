/// Strata の思考段階（OpenAI 互換 `reasoning_effort`）。
///
/// サーバ側は `high` を内部の `xhigh` にマップする。
enum StrataThinkingEffort {
  none,
  low,
  medium,
  high;

  String get label => switch (this) {
        StrataThinkingEffort.none => 'なし',
        StrataThinkingEffort.low => '低',
        StrataThinkingEffort.medium => '中',
        StrataThinkingEffort.high => '高',
      };

  String get subtitle => switch (this) {
        StrataThinkingEffort.none => '思考せずすぐ答える（最速）',
        StrataThinkingEffort.low => '短い思考',
        StrataThinkingEffort.medium => '標準の思考',
        StrataThinkingEffort.high => '強めの思考（精度寄り・遅い）',
      };

  /// `/v1/chat/completions` の `reasoning_effort` 値。
  String get apiValue => name;

  bool get isEnabled => this != StrataThinkingEffort.none;

  static StrataThinkingEffort fromStorage(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'low':
        return StrataThinkingEffort.low;
      case 'medium':
        return StrataThinkingEffort.medium;
      case 'high':
      case 'xhigh':
      case 'max':
        return StrataThinkingEffort.high;
      case 'none':
      case 'off':
      case 'minimal':
      default:
        return StrataThinkingEffort.none;
    }
  }

  String get storageValue => name;
}
