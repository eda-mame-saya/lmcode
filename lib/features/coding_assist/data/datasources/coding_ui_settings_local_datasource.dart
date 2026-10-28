import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/coding_auto_sleep.dart';
import '../../domain/coding_harness_settings.dart';
import '../../domain/coding_prompt_action.dart';
import '../../domain/coding_ui_font_sizes.dart';

/// S16 表示用 UI 設定（SharedPreferences）。
class CodingUiSettingsLocalDataSource {
  CodingUiSettingsLocalDataSource({required SharedPreferences preferences})
    : _preferences = preferences;

  static const _prefMenuFont = 'coding_ui_font_menu';
  static const _prefEditorFont = 'coding_ui_font_editor';
  static const _prefAgentFont = 'coding_ui_font_agent';
  static const _prefIndentSize = 'coding_ui_indent_size';
  static const _prefPromptFavorites = 'coding_ui_prompt_favorites';
  static const _prefAutoSleepWhenFinished =
      'coding_ui_auto_sleep_when_finished';
  static const _prefAutoSleepAfterMinutes =
      'coding_ui_auto_sleep_after_minutes';
  static const _prefHarness = 'coding_ui_harness';

  /// インデント空白の既定（4）。
  static const defaultIndentSize = 4;

  final SharedPreferences _preferences;

  CodingUiFontSizes loadFontSizes() {
    return CodingUiFontSizes(
      menu: CodingUiFontSizes.clamp(
        _preferences.getDouble(_prefMenuFont) ??
            CodingUiFontSizes.defaults.menu,
      ),
      editor: CodingUiFontSizes.clamp(
        _preferences.getDouble(_prefEditorFont) ??
            CodingUiFontSizes.defaults.editor,
      ),
      agent: CodingUiFontSizes.clamp(
        _preferences.getDouble(_prefAgentFont) ??
            CodingUiFontSizes.defaults.agent,
      ),
    );
  }

  Future<void> saveFontSizes(CodingUiFontSizes sizes) async {
    final next = sizes.copyWith();
    await _preferences.setDouble(_prefMenuFont, next.menu);
    await _preferences.setDouble(_prefEditorFont, next.editor);
    await _preferences.setDouble(_prefAgentFont, next.agent);
  }

  /// 2 または 4。それ以外・未設定は [defaultIndentSize]。
  int loadIndentSize() {
    final v = _preferences.getInt(_prefIndentSize);
    if (v == 2 || v == 4) return v!;
    return defaultIndentSize;
  }

  Future<void> saveIndentSize(int indentSize) async {
    final v = indentSize == 2 ? 2 : 4;
    await _preferences.setInt(_prefIndentSize, v);
  }

  /// プロンプト補助のお気に入り（最大2・登録順）。
  List<CodingPromptAction> loadPromptFavorites() {
    final raw = _preferences.getStringList(_prefPromptFavorites) ?? const [];
    return CodingPromptAction.normalizeFavorites(raw);
  }

  CodingAutoSleepSettings loadAutoSleepSettings() {
    final minutes = _preferences.getInt(_prefAutoSleepAfterMinutes) ?? 0;
    return CodingAutoSleepSettings(
      sleepWhenFinished:
          _preferences.getBool(_prefAutoSleepWhenFinished) ?? false,
      sleepAfterMinutes: minutes,
    ).normalized();
  }

  Future<void> saveAutoSleepSettings(CodingAutoSleepSettings settings) async {
    final next = settings.normalized();
    await _preferences.setBool(
      _prefAutoSleepWhenFinished,
      next.sleepWhenFinished,
    );
    await _preferences.setInt(
      _prefAutoSleepAfterMinutes,
      next.sleepAfterMinutes,
    );
  }

  CodingHarnessSettings loadHarness() {
    final raw = _preferences.getString(_prefHarness);
    if (raw == null || raw.isEmpty) return CodingHarnessSettings.defaults;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CodingHarnessSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return CodingHarnessSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return CodingHarnessSettings.defaults;
  }

  Future<void> saveHarness(CodingHarnessSettings settings) async {
    final next = settings.normalized();
    await _preferences.setString(_prefHarness, jsonEncode(next.toJson()));
  }

  Future<void> savePromptFavorites(List<CodingPromptAction> favorites) async {
    final next = CodingPromptAction.normalizeFavorites(
      favorites.map((e) => e.id),
    );
    await _preferences.setStringList(
      _prefPromptFavorites,
      next.map((e) => e.id).toList(growable: false),
    );
  }
}
