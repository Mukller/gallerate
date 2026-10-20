import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки лежат в SharedPreferences — то есть во внешнем хранилище,
/// которое могло остаться от старой версии приложения, быть дописанным
/// вручную или повреждённым. Приложение обязано запускаться в любом случае:
/// падать на чтении одного ключа нельзя.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsRepository repo;

  Future<void> withPrefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    repo = SettingsRepository(await SharedPreferences.getInstance());
  }

  group('albumIds — битые данные', () {
    test('валидный список читается', () async {
      await withPrefs({'album_ids': '["a1","a2"]'});
      expect(repo.albumIds, ['a1', 'a2']);
    });

    test('отсутствующий ключ — пустой список', () async {
      await withPrefs({});
      expect(repo.albumIds, isEmpty);
    });

    test('битый JSON не роняет чтение', () async {
      await withPrefs({'album_ids': '{не json'});
      expect(repo.albumIds, isEmpty);
    });

    test('JSON не-массив игнорируется', () async {
      await withPrefs({'album_ids': '{"a":1}'});
      expect(repo.albumIds, isEmpty);
    });

    test('нестроковые элементы отбрасываются, строки сохраняются', () async {
      await withPrefs({'album_ids': '["ok", 5, null, {"x":1}, "also-ok"]'});
      expect(repo.albumIds, ['ok', 'also-ok']);
    });

    test('пустая строка — пустой список', () async {
      await withPrefs({'album_ids': ''});
      expect(repo.albumIds, isEmpty);
    });

    test('число вместо списка игнорируется', () async {
      await withPrefs({'album_ids': '42'});
      expect(repo.albumIds, isEmpty);
    });
  });

  group('dailyCount', () {
    test('по умолчанию 10', () async {
      await withPrefs({});
      expect(repo.dailyCount, 10);
    });

    test('нормальное значение сохраняется', () async {
      await withPrefs({'daily_count': 25});
      expect(repo.dailyCount, 25);
    });

    // Регрессия: геттер не клампил, и значение из старой версии
    // приложения давало сет из 0 или из 100 фото.
    test('слишком большое значение из prefs обрезается до 50', () async {
      await withPrefs({'daily_count': 500});
      expect(repo.dailyCount, 50);
    });

    test('слишком маленькое значение поднимается до 5', () async {
      await withPrefs({'daily_count': 1});
      expect(repo.dailyCount, 5);
    });

    test('отрицательное значение поднимается до 5', () async {
      await withPrefs({'daily_count': -10});
      expect(repo.dailyCount, 5);
    });

    test('запись тоже клампит', () async {
      await withPrefs({});
      await repo.setDailyCount(999);
      expect(repo.dailyCount, 50);
    });
  });

  group('appearMinutes', () {
    test('по умолчанию 20:00', () async {
      await withPrefs({});
      expect(repo.appearMinutes, 20 * 60);
    });

    test('нормальное значение сохраняется', () async {
      await withPrefs({'appear_minutes': 9 * 60 + 30});
      expect(repo.appearMinutes, 570);
    });

    // Регрессия: 99999 минут означало «1666:39» в интерфейсе и сет,
    // который никогда не генерировался бы.
    test('вне диапазона суток откатывается к 20:00', () async {
      await withPrefs({'appear_minutes': 99999});
      expect(repo.appearMinutes, 20 * 60);
    });

    test('отрицательное значение откатывается к 20:00', () async {
      await withPrefs({'appear_minutes': -50});
      expect(repo.appearMinutes, 20 * 60);
    });

    test('ровно полночь допустима', () async {
      await withPrefs({'appear_minutes': 0});
      expect(repo.appearMinutes, 0);
    });

    test('23:59 допустима', () async {
      await withPrefs({'appear_minutes': 23 * 60 + 59});
      expect(repo.appearMinutes, 23 * 60 + 59);
    });

    test('запись клампит до последней минуты суток', () async {
      await withPrefs({});
      await repo.setAppearMinutes(5000);
      expect(repo.appearMinutes, 24 * 60 - 1);
    });
  });

  group('localeCode', () {
    test('нет ключа — системный язык', () async {
      await withPrefs({});
      expect(repo.localeCode, isNull);
    });

    test('поддерживаемый код читается', () async {
      await withPrefs({'locale': 'ru'});
      expect(repo.localeCode, 'ru');
    });

    test('неизвестный код игнорируется', () async {
      await withPrefs({'locale': 'de'});
      expect(repo.localeCode, isNull,
          reason: 'неподдерживаемый локаль ушёл бы в MaterialApp');
    });

    test('запись null удаляет ключ', () async {
      await withPrefs({'locale': 'ru'});
      await repo.setLocaleCode(null);
      expect(repo.localeCode, isNull);
    });
  });

  group('themeMode', () {
    test('по умолчанию системная', () async {
      await withPrefs({});
      expect(repo.themeMode, ThemeMode.system);
    });

    test('light и dark читаются', () async {
      await withPrefs({'theme_mode': 'light'});
      expect(repo.themeMode, ThemeMode.light);
      await withPrefs({'theme_mode': 'dark'});
      expect(repo.themeMode, ThemeMode.dark);
    });

    test('мусор в значении не ломает чтение', () async {
      await withPrefs({'theme_mode': 'не тема'});
      expect(repo.themeMode, ThemeMode.system);
    });

    test('тема пишется и читается', () async {
      await withPrefs({});
      await repo.setThemeMode(ThemeMode.dark);
      expect(repo.themeMode, ThemeMode.dark);
    });
  });

  group('прочее', () {
    test('onboarded по умолчанию false', () async {
      await withPrefs({});
      expect(repo.onboarded, isFalse);
    });

    test('onboarded пишется', () async {
      await withPrefs({});
      await repo.setOnboarded(true);
      expect(repo.onboarded, isTrue);
    });

    test('permissionGranted по умолчанию false', () async {
      await withPrefs({});
      expect(repo.permissionGranted, isFalse);
    });

    test('clearAll сбрасывает всё', () async {
      await withPrefs({'onboarded': true, 'daily_count': 30});
      await repo.clearAll();
      expect(repo.onboarded, isFalse);
      expect(repo.dailyCount, 10);
    });

    test('альбомы пишутся и читаются', () async {
      await withPrefs({});
      await repo.setAlbumIds(['x', 'y']);
      expect(repo.albumIds, ['x', 'y']);
    });

    test('пустой список альбомов пишется без ошибок', () async {
      await withPrefs({});
      await repo.setAlbumIds(const []);
      expect(repo.albumIds, isEmpty);
    });
  });
}
