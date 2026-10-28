/// AmiVoice 接続エンジン候補（会議向け）。
/// 新規追加：設定画面プルダウン用
enum AmiVoiceEngine {
  general(
    value: '-a-general',
    label: '会話_汎用',
    isRecommended: true,
  ),
  jaE2eGeneral(
    value: '-a2-ja-general',
    label: '日本語E2E_汎用',
  ),
  medical(
    value: '-a-medical',
    label: '会話_医療',
  ),
  bizFinance(
    value: '-a-bizfinance',
    label: '会話_金融',
  ),
  bizInsurance(
    value: '-a-bizinsurance',
    label: '会話_保険',
  );

  const AmiVoiceEngine({
    required this.value,
    required this.label,
    this.isRecommended = false,
  });

  final String value;
  final String label;
  final bool isRecommended;

  String get displayLabel =>
      isRecommended ? '$label ($value) … 推奨' : '$label ($value)';

  static AmiVoiceEngine fromValue(String value) {
    return AmiVoiceEngine.values.firstWhere(
      (e) => e.value == value,
      orElse: () => AmiVoiceEngine.general,
    );
  }
}

/// Gemini 推奨モデル候補。
/// 新規追加：設定画面のデフォルト／プルダウン用
abstract final class GeminiModelPresets {
  static const defaultModel = 'gemini-3.5-flash';

  static const recommended = <String>[
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
  ];
}
