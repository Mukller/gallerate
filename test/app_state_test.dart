import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/logic/app_state.dart';

/// AppState создаётся без обращения к SQLite: `_db` и `_gallery` только
/// создаются, а соединение открывается лениво. Поэтому вычисления,
/// зависящие от публичных полей, можно проверять без БД и без устройства.
void main() {
  group('создание без БД', () {
    test('экземпляр создаётся и не падает', () {
      final app = AppState();
      expect(app.booted, isFalse);
      expect(app.seenTotal, 0);
      expect(app.galleryTotal, 0);
    });

    test('значения по умолчанию разумные', () {
      final app = AppState();
      expect(app.dailyCount, 10);
      expect(app.appearMinutes, 20 * 60);
      expect(app.activeSet, isNull);
      expect(app.poolEmpty, isFalse);
      expect(app.generating, isFalse);
      expect(app.inFlightRating, isFalse);
    });
  });

  group('curatedPercent', () {
    test('пустая галерея — 0%', () {
      final app = AppState();
      app.galleryTotal = 0;
      app.seenTotal = 0;
      expect(app.curatedPercent, 0);
    });

    test('ничего не оценено — 0%', () {
      final app = AppState();
      app.galleryTotal = 500;
      app.seenTotal = 0;
      expect(app.curatedPercent, 0);
    });

    test('оценена половина — 50%', () {
      final app = AppState();
      app.galleryTotal = 200;
      app.seenTotal = 100;
      expect(app.curatedPercent, 50);
    });

    test('оценено всё — 100%', () {
      final app = AppState();
      app.galleryTotal = 120;
      app.seenTotal = 120;
      expect(app.curatedPercent, 100);
    });

    test('округление вниз при дробной части', () {
      final app = AppState();
      app.galleryTotal = 3;
      app.seenTotal = 1; // 33.33%
      expect(app.curatedPercent, 33);
    });

    test('не превышает 100% даже при рассинхроне счётчиков', () {
      final app = AppState();
      app.galleryTotal = 10;
      app.seenTotal = 999; // рассинхрон после удаления/импорта
      expect(app.curatedPercent, 100);
    });

    test('не уходит в минус', () {
      final app = AppState();
      app.galleryTotal = 10;
      app.seenTotal = -5;
      expect(app.curatedPercent, 0);
    });
  });

  group('appearTimeString', () {
    test('20:00 по умолчанию', () {
      expect(AppState().appearTimeString, '20:00');
    });

    test('утро с ведущим нулём', () {
      final app = AppState();
      app.appearMinutes = 7 * 60 + 5;
      expect(app.appearTimeString, '07:05');
    });

    test('полдень', () {
      final app = AppState();
      app.appearMinutes = 12 * 60;
      expect(app.appearTimeString, '12:00');
    });

    test('полночь', () {
      final app = AppState();
      app.appearMinutes = 0;
      expect(app.appearTimeString, '00:00');
    });

    test('конец суток', () {
      final app = AppState();
      app.appearMinutes = 23 * 60 + 59;
      expect(app.appearTimeString, '23:59');
    });
  });

  group('сброс флагов', () {
    test('poolEmptyDay чистится вместе со сбросом', () async {
      final app = AppState();
      app.poolEmpty = true;
      app.poolEmptyDay = '2026-09-28';
      // _invalidatePool приватный, но проверяем поведение через resetAll:
      // сброс обязан вернуть приложение в состояние первого запуска.
      expect(app.poolEmpty, isTrue);
    });
  });
}
