import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/core/notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  group('computeNextTrigger', () {
    // Регрессия: пакет timezone отдаёт tz.local == UTC по умолчанию.
    // Из-за этого напоминание на «20:00» срабатывало в 20:00 UTC, то есть
    // на три часа позже в Минске (UTC+3). Тест фиксирует, что время
    // трактуется в переданной зоне, а не в UTC.
    test('время трактуется в переданной зоне, а не в UTC', () {
      tz.setLocalLocation(tz.getLocation('Europe/Minsk'));
      final minsk = tz.getLocation('Europe/Minsk');

      final now = tz.TZDateTime(minsk, 2026, 9, 28, 10, 0);
      final when = computeNextTrigger(
        location: minsk,
        now: now,
        minutes: 20 * 60,
      );

      expect(when.hour, 20);
      expect(when.minute, 0);
      expect(when.day, 28);
      // Минск = UTC+3 без перевода времени. Если бы планировалось в UTC,
      // вместо 20:00 получилось бы 17:00 при now = 10:00 UTC.
      final asUtc = when.toUtc();
      expect(asUtc.hour, 17, reason: '20:00 Минск = 17:00 UTC');
    });

    test('Европа/Берлин — UTC+2 летом, сдвиг применяется', () {
      final berlin = tz.getLocation('Europe/Berlin');
      final now = tz.TZDateTime(berlin, 2026, 7, 1, 10, 0);
      final when =
          computeNextTrigger(location: berlin, now: now, minutes: 20 * 60);
      expect(when.hour, 20);
    });

    test('сегодня время ещё не наступило — сегодня', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 9, 28, 10, 0);
      final when =
          computeNextTrigger(location: minsk, now: now, minutes: 20 * 60);
      expect(when.day, 28);
      expect(when.isAfter(now), isTrue);
    });

    test('сегодня время уже прошло — завтра', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 9, 28, 21, 0);
      final when =
          computeNextTrigger(location: minsk, now: now, minutes: 20 * 60);
      expect(when.day, 29);
      expect(when.hour, 20);
      expect(when.isAfter(now), isTrue);
    });

    test('ровно в момент срабатывания — ждём следующего дня', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 9, 28, 20, 0);
      final when =
          computeNextTrigger(location: minsk, now: now, minutes: 20 * 60);
      expect(when.day, 29);
    });

    test('полночь: minutes = 0', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 9, 28, 23, 30);
      final when = computeNextTrigger(location: minsk, now: now, minutes: 0);
      expect(when.day, 29);
      expect(when.hour, 0);
    });

    test('23:59', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 9, 28, 10, 0);
      final when =
          computeNextTrigger(location: minsk, now: now, minutes: 23 * 60 + 59);
      expect(when.hour, 23);
      expect(when.minute, 59);
      expect(when.day, 28);
    });

    test('переход через границу месяца', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 9, 30, 22, 0);
      final when =
          computeNextTrigger(location: minsk, now: now, minutes: 20 * 60);
      expect(when.month, 10);
      expect(when.day, 1);
    });

    test('переход через границу года', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 12, 31, 22, 0);
      final when =
          computeNextTrigger(location: minsk, now: now, minutes: 20 * 60);
      expect(when.year, 2027);
      expect(when.month, 1);
      expect(when.day, 1);
    });

    test('перевод на летнее время не сбивает время суток', () {
      final berlin = tz.getLocation('Europe/Berlin');
      // В Берлине перевод в последнее воскресенье марта: +2 часа.
      final before = tz.TZDateTime(berlin, 2026, 3, 28, 12, 0);
      final after = tz.TZDateTime(berlin, 2026, 3, 30, 12, 0);

      for (final now in [before, after]) {
        final when =
            computeNextTrigger(location: berlin, now: now, minutes: 20 * 60);
        expect(when.hour, 20,
            reason: 'час должен остаться 20:00 при любом смещении');
      }
    });

    test('зона UTC+12 — вечернее время не съезжает', () {
      final nz = tz.getLocation('Pacific/Auckland');
      final now = tz.TZDateTime(nz, 2026, 9, 28, 9, 0);
      final when = computeNextTrigger(location: nz, now: now, minutes: 20 * 60);
      expect(when.hour, 20);
    });

    test('зона UTC-8 — вечернее время не съезжает', () {
      final la = tz.getLocation('America/Los_Angeles');
      final now = tz.TZDateTime(la, 2026, 9, 28, 9, 0);
      final when = computeNextTrigger(location: la, now: now, minutes: 20 * 60);
      expect(when.hour, 20);
    });

    test('минуты нормализуются в часы и минуты', () {
      final minsk = tz.getLocation('Europe/Minsk');
      final now = tz.TZDateTime(minsk, 2026, 9, 28, 6, 0);
      final when =
          computeNextTrigger(location: minsk, now: now, minutes: 9 * 60 + 5);
      expect(when.hour, 9);
      expect(when.minute, 5);
    });
  });
}
