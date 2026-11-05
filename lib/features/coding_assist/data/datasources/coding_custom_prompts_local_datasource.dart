import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/coding_custom_prompt_id.dart';
import '../../domain/coding_custom_prompts.dart';

/// カスタムプロンプト上書き（SharedPreferences）。
class CodingCustomPromptsLocalDataSource {
  CodingCustomPromptsLocalDataSource({required SharedPreferences preferences})
    : _preferences = preferences;

  static const prefKey = 'coding_custom_prompts';

  final SharedPreferences _preferences;

  /// 端末から読み、[CodingCustomPrompts] に反映する。
  Map<String, String> loadAndBind() {
    final map = load();
    CodingCustomPrompts.load(map);
    return map;
  }

  Map<String, String> load() {
    final raw = _preferences.getString(prefKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, String>{};
      for (final e in decoded.entries) {
        final id = CodingCustomPromptId.tryParse(e.key?.toString());
        if (id == null) continue;
        final text = e.value?.toString() ?? '';
        if (text.trim().isEmpty) continue;
        out[id.key] = text;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveAll(Map<String, String> overrides) async {
    final cleaned = <String, String>{
      for (final e in overrides.entries)
        if (CodingCustomPromptId.tryParse(e.key) != null &&
            e.value.trim().isNotEmpty)
          e.key: e.value,
    };
    if (cleaned.isEmpty) {
      await _preferences.remove(prefKey);
    } else {
      await _preferences.setString(prefKey, jsonEncode(cleaned));
    }
    CodingCustomPrompts.load(cleaned);
  }

  Future<void> saveOne(CodingCustomPromptId id, String text) async {
    final next = Map<String, String>.from(load());
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      next.remove(id.key);
    } else {
      next[id.key] = text;
    }
    await saveAll(next);
  }

  Future<void> clearOne(CodingCustomPromptId id) async {
    final next = Map<String, String>.from(load());
    next.remove(id.key);
    await saveAll(next);
  }
}
