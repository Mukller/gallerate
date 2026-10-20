import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const _kOnboarded = 'onboarded';
  static const _kDailyCount = 'daily_count';
  static const _kAppearMinutes = 'appear_minutes';
  static const _kThemeMode = 'theme_mode';
  static const _kLocale = 'locale';
  static const _kAlbumIds = 'album_ids';
  static const _kPermission = 'permission_granted';

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool v) => _prefs.setBool(_kOnboarded, v);

  bool get permissionGranted => _prefs.getBool(_kPermission) ?? false;
  Future<void> setPermissionGranted(bool v) => _prefs.setBool(_kPermission, v);

  /// Размер сета. Клампится при чтении, а не только при записи: в prefs
  /// могло остаться значение из старой версии приложения или из ручной
  /// правки, и 0 фото в сете или сотня — это поломанный сет.
  int get dailyCount => (_prefs.getInt(_kDailyCount) ?? 10).clamp(5, 50);
  Future<void> setDailyCount(int v) =>
      _prefs.setInt(_kDailyCount, v.clamp(5, 50));

  /// Минуты от полуночи. Значение вне 0..1439 сделало бы время появления
  /// невозможным (сет не генерировался бы никогда), а в интерфейсе
  /// показывалось «1666:39».
  int get appearMinutes {
    final v = _prefs.getInt(_kAppearMinutes) ?? 20 * 60;
    return v >= 0 && v < 24 * 60 ? v : 20 * 60;
  }

  Future<void> setAppearMinutes(int v) =>
      _prefs.setInt(_kAppearMinutes, v.clamp(0, 24 * 60 - 1));

  ThemeMode get themeMode {
    switch (_prefs.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      _prefs.setString(_kThemeMode, mode.name);

  /// Код языка, только если он реально поддерживается.
  /// Неизвестное значение (оставшееся от старой версии или дописанное
  /// вручную) иначе уходит в MaterialApp как unsupported locale.
  static const _supportedLocales = {'en', 'ru'};

  String? get localeCode {
    final code = _prefs.getString(_kLocale);
    if (code == null || !_supportedLocales.contains(code)) return null;
    return code;
  }

  Future<void> setLocaleCode(String? code) async {
    if (code == null) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, code);
    }
  }

  /// Идентификаторы выбранных альбомов.
  ///
  /// Разбор защищён: значение приходит из SharedPreferences, то есть из
  /// непроверенного внешнего хранилища. Раньше битый JSON здесь ронял
  /// AppState.init(), и приложение открывалось белым экраном — упасть
  /// должно только чтение одного ключа, а не весь запуск.
  List<String> get albumIds {
    try {
      final raw = _prefs.getString(_kAlbumIds);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> setAlbumIds(List<String> ids) =>
      _prefs.setString(_kAlbumIds, jsonEncode(ids));

  Future<void> clearAll() => _prefs.clear();
}
