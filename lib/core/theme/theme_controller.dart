import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/settings_store.dart';

class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const String _themeKey = 'theme_mode';
  ThemeMode _themeMode = ThemeMode.dark;

  ThemeMode get mode =>
      _themeMode == ThemeMode.system ? ThemeMode.dark : _themeMode;
  ThemeMode get themeMode => mode;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeKey);
    _themeMode = _themeModeFromString(raw);
    if (_themeMode != SettingsStore.instance.themeMode) {
      await SettingsStore.instance.setThemeMode(_themeMode);
    }
    // Persist migration if legacy "system" was stored.
    if (raw == 'system') {
      await prefs.setString(_themeKey, 'dark');
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode == ThemeMode.system ? ThemeMode.dark : mode;
    await SettingsStore.instance.setThemeMode(_themeMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, _themeModeToString(_themeMode));
    notifyListeners();
  }

  ThemeMode _themeModeFromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        // System default removed — treat missing/legacy as Dark.
        return ThemeMode.dark;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
      case ThemeMode.system:
        return 'dark';
    }
  }
}
