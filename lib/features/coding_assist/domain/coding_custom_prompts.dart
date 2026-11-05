import 'coding_custom_prompt_id.dart';

/// 実行時に参照するカスタムプロンプト上書き。
///
/// 起動時と S17 保存時に [load] する。未設定や空文字は組み込み既定を使う。
abstract final class CodingCustomPrompts {
  static final Map<String, String> _overrides = {};

  /// SharedPreferences 等から読み込んだ上書きを反映する。
  static void load(Map<String, String> overrides) {
    _overrides
      ..clear()
      ..addAll({
        for (final e in overrides.entries)
          if (e.key.trim().isNotEmpty && e.value.trim().isNotEmpty)
            e.key.trim(): e.value,
      });
  }

  /// 現在の上書き（空は含まない）。
  static Map<String, String> snapshot() =>
      Map<String, String>.unmodifiable(_overrides);

  static String? overrideOf(CodingCustomPromptId id) {
    final v = _overrides[id.key]?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  static bool isCustomized(CodingCustomPromptId id) => overrideOf(id) != null;

  /// 上書きがあればそれ、なければ [builtIn]。
  static String apply(CodingCustomPromptId id, String builtIn) {
    return overrideOf(id) ?? builtIn;
  }

  /// 編集中テキストをプレースホルダ置換する（テスト用）。
  ///
  /// `{{name}}` を [vars] の値で置き換える。未定義はそのまま残す。
  static String substitute(String template, Map<String, String> vars) {
    if (vars.isEmpty || !template.contains('{{')) return template;
    var out = template;
    for (final e in vars.entries) {
      out = out.replaceAll('{{${e.key}}}', e.value);
    }
    return out;
  }
}
