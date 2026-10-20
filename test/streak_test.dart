import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/db.dart';

/// Серия считается по ISO-строкам, отсортированным по убыванию.
List<String> days(List<DateTime> ds) =>
    ds.map(AppDb.dayKey).toList(growable: false);

DateTime d(int y, int m, int dd) => DateTime(y, m, dd);

void main() {
  group('AppDb.computeStreak', () {
    test('пусто — серия 0', () {
      expect(AppDb.computeStreak(const [], d(2026, 9, 28)), 0);
    });

    test('оценка сегодня — серия 1', () {
      final now = d(2026, 9, 28);
      expect(AppDb.computeStreak(days([d(2026, 9, 28)]), now), 1);
    });

    test('три дня подряд до сегодня — серия 3', () {
      final now = d(2026, 9, 28);
      final active = days([d(2026, 9, 28), d(2026, 9, 27), d(2026, 9, 26)]);
      expect(AppDb.computeStreak(active, now), 3);
    });

    test('серия может начаться вчера (сегодня ещё не оценено)', () {
      final now = d(2026, 9, 28);
      final active = days([d(2026, 9, 27), d(2026, 9, 26)]);
      expect(AppDb.computeStreak(active, now), 2);
    });

    test('пропуск дня разрывает серию', () {
      final now = d(2026, 9, 28);
      // 28, 27 есть, 26 нет, 25 есть -> серия 2
      final active = days([d(2026, 9, 28), d(2026, 9, 27), d(2026, 9, 25)]);
      expect(AppDb.computeStreak(active, now), 2);
    });

    test('старые дни без сегодня и без вчера — серия 0', () {
      final now = d(2026, 9, 28);
      final active = days([d(2026, 9, 20), d(2026, 9, 19)]);
      expect(AppDb.computeStreak(active, now), 0);
    });

    // Регрессия: перевод времени. В сутках 23 или 25 часов, поэтому
    // subtract(Duration(days:1)) от полуночи даёт не полночь.
    test('переживает перевод на летнее время', () {
      // В европейской зоне перевод в конце марта.
      final now = DateTime(2026, 3, 30, 15);
      final active = days([d(2026, 3, 30), d(2026, 3, 29), d(2026, 3, 28)]);
      expect(AppDb.computeStreak(active, now), 3);
    });

    test('переживает перевод на зимнее время', () {
      final now = DateTime(2026, 10, 26, 15);
      final active = days([d(2026, 10, 26), d(2026, 10, 25), d(2026, 10, 24)]);
      expect(AppDb.computeStreak(active, now), 3);
    });

    test('переход через границу месяца', () {
      final now = d(2026, 3, 1);
      final active = days([d(2026, 3, 1), d(2026, 2, 28), d(2026, 2, 27)]);
      expect(AppDb.computeStreak(active, now), 3);
    });

    test('переход через границу года', () {
      final now = d(2026, 1, 2);
      final active = days([d(2026, 1, 2), d(2026, 1, 1), d(2025, 12, 31)]);
      expect(AppDb.computeStreak(active, now), 3);
    });

    test('длинная серия', () {
      final now = d(2026, 9, 28);
      final list = <DateTime>[];
      for (var i = 0; i < 40; i++) {
        list.add(DateTime(2026, 9, 28).subtract(Duration(days: i)));
      }
      // Строим ключи вручную: Duration-вычитание тут только для генерации.
      expect(AppDb.computeStreak(days(list), now), greaterThanOrEqualTo(39));
    });

    test('битые строки пропускаются, а не роняют', () {
      final now = d(2026, 9, 28);
      final active = ['2026-09-28', 'мусор', '2026-09-27', 'xx-yy'];
      expect(AppDb.computeStreak(active, now), 2);
    });

    test('пустой день не считается разрывом', () {
      final now = d(2026, 9, 28);
      final active = days([d(2026, 9, 28), d(2026, 9, 27)]);
      expect(AppDb.computeStreak(active, now), 2);
    });
  });
}
