import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/db.dart';
import 'package:gallerate/data/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Тесты слоя БД на настоящем SQLite (sqflite_common_ffi), без устройства.
/// Именно здесь живут самые опасные баги: потеря флагов при переоценке,
/// фильтрация удалённых, подсчёт серии и импорт.
/// Путь к тестовой БД через ту же фабрику, что и у приложения.
Future<String> testDbPath() async {
  final dir = await databaseFactory.getDatabasesPath();
  return '$dir/${AppDb.databaseName}';
}

/// Оценка одного ассета — через публичный batch-запрос.
Future<int?> ratingOf(String id) async {
  final map = await AppDb.instance.ratingsForAssets([id]);
  return map[id];
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    AppDb.databaseName = 'gallerate_test.db';
    await AppDb.instance.close();
    await deleteDatabase(await testDbPath());
  });

  tearDown(() async {
    await AppDb.instance.close();
  });

  group('markSeen', () {
    test('записывает оценку и день', () async {
      await AppDb.instance.markSeen('a1', 7);
      final rating = await ratingOf('a1');
      expect(rating, 7);
      expect(await AppDb.instance.totalSeen(), 1);
    });

    test('повторная оценка перезаписывает рейтинг', () async {
      await AppDb.instance.markSeen('a1', 7);
      await AppDb.instance.markSeen('a1', 2);
      expect(await ratingOf('a1'), 2);
      expect(await AppDb.instance.totalSeen(), 1);
    });

    // Регрессия: старая реализация делала INSERT OR REPLACE, и переоценка
    // обнуляла sorted/deleted — разложенные в галерею фото попадали бы
    // в сортировку повторно и давали дубликаты.
    test('переоценка НЕ сбрасывает флаг sorted', () async {
      await AppDb.instance.markSeen('a1', 8);
      await AppDb.instance.markSorted(['a1']);
      await AppDb.instance.markSeen('a1', 3);
      final rows = await AppDb.instance.unsortedRatedRows();
      expect(rows, isEmpty, reason: 'sorted должен сохраниться');
      expect(await AppDb.instance.sortedCount(), 1);
    });

    test('переоценка НЕ сбрасывает флаг deleted', () async {
      await AppDb.instance.markSeen('a1', 8);
      await AppDb.instance.markDeleted(['a1']);
      await AppDb.instance.markSeen('a1', 5);
      // Фото удалено из галереи — снова попадать в totalSeen не должно.
      expect(await AppDb.instance.totalSeen(), 0);
    });
  });

  group('clearRating', () {
    test('удаляет запись целиком', () async {
      await AppDb.instance.markSeen('a1', 7);
      expect(await ratingOf('a1'), 7);

      await AppDb.instance.clearRating('a1');

      expect(await ratingOf('a1'), isNull,
          reason: 'оценка должна исчезнуть, а не стать нулём');
      expect(await AppDb.instance.totalSeen(), 0);
    });

    // Регрессия: если бы оценка обнулялась (rating = 0), фото осталось бы
    // в базе и попало в историю и статистику как пропущенное, а также
    // продолжало считаться просмотренным.
    test('фото возвращается в непросмотренные', () async {
      await AppDb.instance.markSeen('a1', 7);
      await AppDb.instance.clearRating('a1');

      expect(await AppDb.instance.seenIds(), isNot(contains('a1')));
      final stats = await AppDb.instance.dayStats();
      expect(stats.values.fold<int>(0, (s, d) => s + d.ratedTotal), 0,
          reason: 'в статистике дня не должно остаться следов');
    });

    test('не трогает остальные фото', () async {
      await AppDb.instance.markSeen('a1', 7);
      await AppDb.instance.markSeen('a2', 8);

      await AppDb.instance.clearRating('a1');

      expect(await ratingOf('a2'), 8);
      expect(await AppDb.instance.totalSeen(), 1);
    });

    test('снятие несуществующей оценки не падает', () async {
      await AppDb.instance.clearRating('нет-такого');
      expect(await AppDb.instance.totalSeen(), 0);
    });
  });

  group('сортировка по дате съёмки', () {
    test('дата съёмки сохраняется', () async {
      await AppDb.instance.markSeen('a1', 5, takenAt: 1000);

      final rows = await AppDb.instance.lowRatedRows();
      expect(rows.first.takenAt, 1000);
    });

    test('переоценка не затирает известную дату съёмки', () async {
      await AppDb.instance.markSeen('a1', 5, takenAt: 1000);
      await AppDb.instance.markSeen('a1', 8);

      final rows = await AppDb.instance.rowsByRating(8);
      expect(rows.first.takenAt, 1000,
          reason: 'дата съёмки не должна пропасть при переоценке');
    });

    test('по дате — от старых к новым', () async {
      await AppDb.instance.markSeen('new', 5, takenAt: 3000);
      await AppDb.instance.markSeen('old', 5, takenAt: 1000);
      await AppDb.instance.markSeen('mid', 5, takenAt: 2000);

      final rows = await AppDb.instance.lowRatedRows(sort: PhotoSort.takenDate);
      expect(rows.map((r) => r.id).toList(), ['old', 'mid', 'new']);
    });

    test('фото без даты съёмки уходят в конец', () async {
      await AppDb.instance.markSeen('withdate', 5, takenAt: 1000);
      await AppDb.instance.markSeen('nodate', 5);

      final rows = await AppDb.instance.lowRatedRows(sort: PhotoSort.takenDate);
      expect(rows.first.id, 'withdate');
      expect(rows.last.id, 'nodate',
          reason: 'неизвестная дата не должна вставать в случайное место');
    });

    test('по умолчанию порядок по оценке', () async {
      await AppDb.instance.markSeen('a', 5, takenAt: 1000);
      await AppDb.instance.markSeen('b', 2, takenAt: 9000);

      final rows = await AppDb.instance.lowRatedRows();
      expect(rows.first.id, 'b', reason: 'худшие сверху — как было');
    });
  });

  group('totalSeen', () {
    test('не считает удалённые фото', () async {
      await AppDb.instance.markSeen('a1', 7);
      await AppDb.instance.markSeen('a2', 8);
      await AppDb.instance.markDeleted(['a1']);
      expect(await AppDb.instance.totalSeen(), 1);
    });

    test('пустая база даёт 0', () async {
      expect(await AppDb.instance.totalSeen(), 0);
    });
  });

  group('dayStats', () {
    test('группирует по дням, делит на категории', () async {
      await AppDb.instance.markSeen('a', 8); // like
      await AppDb.instance.markSeen('b', 2); // dislike
      await AppDb.instance.markSeen('c', 0); // skip
      final stats = await AppDb.instance.dayStats();
      final today = AppDb.dayKey(DateTime.now());
      expect(stats[today]!.likes, 1);
      expect(stats[today]!.dislikes, 1);
      expect(stats[today]!.skips, 1);
      expect(stats[today]!.ratedTotal, 3);
    });

    test('пропуски попадают в дни, где нет оценок', () async {
      await AppDb.instance.markSeen('a', 0);
      final stats = await AppDb.instance.dayStats();
      final today = AppDb.dayKey(DateTime.now());
      expect(stats[today]!.skips, 1);
      expect(stats[today]!.likes, 0);
    });

    test('удалённые не учитываются', () async {
      await AppDb.instance.markSeen('a', 8);
      await AppDb.instance.markDeleted(['a']);
      final stats = await AppDb.instance.dayStats();
      final today = AppDb.dayKey(DateTime.now());
      expect(stats[today], isNull);
    });
  });

  group('ratingCounts / countByRating', () {
    test('считает по каждой оценке', () async {
      await AppDb.instance.markSeen('a', 7);
      await AppDb.instance.markSeen('b', 7);
      await AppDb.instance.markSeen('c', 9);
      final counts = await AppDb.instance.ratingCounts();
      expect(counts[7], 2);
      expect(counts[9], 1);
      expect(await AppDb.instance.countByRating(7), 2);
    });

    test('пропуски не попадают в ratingCounts', () async {
      await AppDb.instance.markSeen('a', 0);
      expect(await AppDb.instance.ratingCounts(), isEmpty);
      expect(await AppDb.instance.countByRating(0), 1);
    });
  });

  group('низкие оценки (очередь уборки)', () {
    test('lowRatedRows отдаёт только 1..5 без удалённых', () async {
      await AppDb.instance.markSeen('bad1', 1);
      await AppDb.instance.markSeen('bad2', 5);
      await AppDb.instance.markSeen('good', 9);
      await AppDb.instance.markSeen('bad3', 3);
      await AppDb.instance.markDeleted(['bad2']);
      final rows = await AppDb.instance.lowRatedRows();
      final ids = rows.map((r) => r.id).toSet();
      expect(ids, {'bad1', 'bad3'});
    });

    test('skip не попадает в очередь уборки', () async {
      await AppDb.instance.markSeen('s', 0);
      expect(await AppDb.instance.lowRatedRows(), isEmpty);
    });

    test('порядок: сначала худшие', () async {
      await AppDb.instance.markSeen('a', 4);
      await AppDb.instance.markSeen('b', 1);
      final rows = await AppDb.instance.lowRatedRows();
      expect(rows.first.id, 'b');
    });
  });

  group('sets', () {
    test('создание, продвижение и закрытие', () async {
      final id = await AppDb.instance.createSet(['a', 'b', 'c'], '2026-09-28');

      var set = await AppDb.instance.activeSet();
      expect(set!.assetIds, ['a', 'b', 'c']);
      expect(set.cursor, 0);
      expect(set.hasPending, isTrue);
      expect(set.currentId, 'a');

      await AppDb.instance.advanceCursor(id, 1);
      set = await AppDb.instance.activeSet();
      expect(set!.cursor, 1);
      expect(set.currentId, 'b');

      await AppDb.instance.completeSet(id);
      expect(await AppDb.instance.activeSet(), isNull);
    });

    test('activeSet берёт последний незакрытый', () async {
      await AppDb.instance.createSet(['old'], '2026-09-27');
      await AppDb.instance.createSet(['new1', 'new2'], '2026-09-28');
      final set = await AppDb.instance.activeSet();
      expect(set!.day, '2026-09-28');
      expect(set.assetIds, ['new1', 'new2']);
    });

    test('seenIds возвращает всё, включая пропуски', () async {
      await AppDb.instance.markSeen('a', 5);
      await AppDb.instance.markSeen('b', 0);
      final ids = await AppDb.instance.seenIds();
      expect(ids, {'a', 'b'});
    });
  });

  group('ratingsForAssets', () {
    test('отдаёт только существующие', () async {
      await AppDb.instance.markSeen('a', 7);
      await AppDb.instance.markSeen('b', 0);
      final map = await AppDb.instance.ratingsForAssets(['a', 'b', 'missing']);
      expect(map, {'a': 7, 'b': 0});
    });

    test('пустой список не ломает запрос', () async {
      expect(await AppDb.instance.ratingsForAssets(const []), isEmpty);
    });

    test('работает на большом списке (чанкование параметров)', () async {
      final ids = List.generate(1200, (i) => 'id$i');
      for (var i = 0; i < ids.length; i += 3) {
        await AppDb.instance.markSeen(ids[i], (i % 10) + 1);
      }
      final map = await AppDb.instance.ratingsForAssets(ids);
      expect(map.length, 400);
      expect(map['id0'], 1);
      expect(map['id3'], 4);
    });
  });

  group('экспорт / импорт', () {
    test('allRatingMaps отдаёт всё', () async {
      await AppDb.instance.markSeen('a', 7);
      await AppDb.instance.markSeen('b', 2);
      final rows = await AppDb.instance.allRatingMaps();
      expect(rows.length, 2);
    });

    test('импорт добавляет новые записи', () async {
      final (added, updated) = await AppDb.instance.upsertRatings([
        {'id': 'x', 'rating': 8, 'day': '2026-09-28', 'rated_at': 1},
        {'id': 'y', 'rating': 3, 'day': '2026-09-28', 'rated_at': 2},
      ]);
      expect(added, 2);
      expect(updated, 0);
      expect(await AppDb.instance.totalSeen(), 2);
    });

    test('импорт обновляет существующие без дублей', () async {
      await AppDb.instance.markSeen('x', 8);
      final (added, updated) = await AppDb.instance.upsertRatings([
        {'id': 'x', 'rating': 2, 'day': '2026-09-28', 'rated_at': 1},
      ]);
      expect(added, 0);
      expect(updated, 1);
      expect(await AppDb.instance.totalSeen(), 1);
      expect(await ratingOf('x'), 2);
    });

    test('импорт игнорирует мусорные значения', () async {
      final (added, updated) = await AppDb.instance.upsertRatings([
        {'id': 'ok', 'rating': 5},
        {'id': 'bad', 'rating': 99},
      ]);
      expect(added, 1);
      expect(updated, 0);
      expect(await AppDb.instance.totalSeen(), 1);
    });

    test('импорт игнорирует не-объекты и строковые рейтинги', () async {
      final rows = <Map<String, Object?>>[];
      final dynamic junk = <Object?>[1, 'два', null];
      for (final item in junk) {
        if (item is Map) rows.add(Map<String, Object?>.from(item));
      }
      // rating приходит строкой — обязана отброситься проверкой 1..10.
      final mixed = <Map<String, Object?>>[
        ...rows,
        {'id': 'strRating', 'rating': 'не число'},
      ];
      final (added, updated) = await AppDb.instance.upsertRatings(mixed);
      expect(added, 0);
      expect(updated, 0);
    });

    test('импорт без дня и времени подставляет текущие', () async {
      await AppDb.instance.upsertRatings([
        {'id': 'x', 'rating': 5},
      ]);
      final rows = await AppDb.instance.allRatingMaps();
      expect(rows.first['day'], AppDb.dayKey(DateTime.now()));
      expect(rows.first['rated_at'], isNotNull);
    });
  });

  group('сортировка в галерею', () {
    test('unsorted → markSorted → sorted', () async {
      await AppDb.instance.markSeen('a', 9);
      await AppDb.instance.markSeen('b', 7);
      expect(await AppDb.instance.unsortedCount(), 2);

      await AppDb.instance.markSorted(['a']);
      expect(await AppDb.instance.unsortedCount(), 1);
      expect(await AppDb.instance.sortedCount(), 1);

      await AppDb.instance.markAllUnsorted();
      expect(await AppDb.instance.unsortedCount(), 2);
      expect(await AppDb.instance.sortedCount(), 0);
    });

    test('markSorted на пустом списке не падает', () async {
      await AppDb.instance.markSorted(const []);
      expect(await AppDb.instance.sortedCount(), 0);
    });

    test('markDeleted на пустом списке не падает', () async {
      await AppDb.instance.markDeleted(const []);
      expect(await AppDb.instance.totalSeen(), 0);
    });
  });

  group('currentStreak через БД', () {
    test('пустая база — серия 0', () async {
      expect(await AppDb.instance.currentStreak(), 0);
    });

    test('оценка сегодня даёт серию 1', () async {
      await AppDb.instance.markSeen('a', 7);
      expect(await AppDb.instance.currentStreak(), 1);
    });

    test('пропуски тоже засчитывают день', () async {
      await AppDb.instance.markSeen('a', 0);
      expect(await AppDb.instance.currentStreak(), 1);
    });
  });

  group('resetAll', () {
    test('чистит фото и наборы', () async {
      await AppDb.instance.markSeen('a', 7);
      await AppDb.instance.createSet(['a'], '2026-09-28');
      await AppDb.instance.resetAll();
      expect(await AppDb.instance.totalSeen(), 0);
      expect(await AppDb.instance.activeSet(), isNull);
    });
  });
}
