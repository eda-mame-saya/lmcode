import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme.dart';
import 'app_color_tokens.dart';

/// アプリ全体の外観（ThemeMode＋個別色オーバーライド）。
class AppThemeController extends ChangeNotifier {
  AppThemeController({required SharedPreferences preferences})
      : _preferences = preferences,
        _themeMode = _decodeMode(preferences.getString(_prefThemeMode)),
        _lightOverrides = _decodeOverrides(
          preferences.getString(_prefColorsLight),
        ),
        _darkOverrides = _decodeOverrides(
          preferences.getString(_prefColorsDark),
        );

  static const _prefThemeMode = 'app_theme_mode';
  static const _prefColorsLight = 'app_color_overrides_light';
  static const _prefColorsDark = 'app_color_overrides_dark';

  final SharedPreferences _preferences;
  ThemeMode _themeMode;
  Map<String, int> _lightOverrides;
  Map<String, int> _darkOverrides;

  ThemeMode get themeMode => _themeMode;

  AppColors get lightColors =>
      AppColors.light.applyOverrides(_lightOverrides);

  AppColors get darkColors => AppColors.dark.applyOverrides(_darkOverrides);

  AppColors colorsFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkColors : lightColors;

  AppColors defaultsFor(Brightness brightness) =>
      brightness == Brightness.dark ? AppColors.dark : AppColors.light;

  bool hasOverride(Brightness brightness, AppColorToken token) {
    final map =
        brightness == Brightness.dark ? _darkOverrides : _lightOverrides;
    return map.containsKey(token.id);
  }

  bool hasAnyOverride(Brightness brightness) {
    final map =
        brightness == Brightness.dark ? _darkOverrides : _lightOverrides;
    return map.isNotEmpty;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    await _preferences.setString(_prefThemeMode, _encodeMode(mode));
    notifyListeners();
  }

  Future<void> setColorOverride({
    required Brightness brightness,
    required AppColorToken token,
    required Color color,
  }) async {
    final defaults = defaultsFor(brightness);
    final map = Map<String, int>.from(
      brightness == Brightness.dark ? _darkOverrides : _lightOverrides,
    );
    final argb = color.toARGB32();
    if (token.read(defaults).toARGB32() == argb) {
      map.remove(token.id);
    } else {
      map[token.id] = argb;
    }
    await _persistOverrides(brightness, map);
  }

  Future<void> clearColorOverride({
    required Brightness brightness,
    required AppColorToken token,
  }) async {
    final map = Map<String, int>.from(
      brightness == Brightness.dark ? _darkOverrides : _lightOverrides,
    );
    if (!map.containsKey(token.id)) return;
    map.remove(token.id);
    await _persistOverrides(brightness, map);
  }

  Future<void> clearAllColorOverrides(Brightness brightness) async {
    final map =
        brightness == Brightness.dark ? _darkOverrides : _lightOverrides;
    if (map.isEmpty) return;
    await _persistOverrides(brightness, <String, int>{});
  }

  Future<void> _persistOverrides(
    Brightness brightness,
    Map<String, int> map,
  ) async {
    if (brightness == Brightness.dark) {
      _darkOverrides = map;
      await _preferences.setString(_prefColorsDark, jsonEncode(map));
    } else {
      _lightOverrides = map;
      await _preferences.setString(_prefColorsLight, jsonEncode(map));
    }
    notifyListeners();
  }

  static String _encodeMode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  static ThemeMode _decodeMode(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static Map<String, int> _decodeOverrides(String? raw) {
    if (raw == null || raw.isEmpty) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      final out = <String, int>{};
      for (final entry in decoded.entries) {
        final key = entry.key;
        final value = entry.value;
        if (key is! String) continue;
        if (AppColorToken.byId(key) == null) continue;
        final argb = value is int
            ? value
            : value is num
                ? value.toInt()
                : null;
        if (argb == null) continue;
        out[key] = argb;
      }
      return out;
    } catch (_) {
      return <String, int>{};
    }
  }
}
