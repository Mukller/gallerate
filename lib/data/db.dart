import 'package:sqflite/sqflite.dart';

import 'models.dart';
import 'rating_store.dart';

class AppDb implements RatingStore {
  AppDb._();

  static final AppDb instance = AppDb._();

  /// Имя файла БД. В тестах подменяется, чтобы не трогать боевые данные.
  static String databaseName = 'gallerate.db';

  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  /// Закрывает соединение. Нужно между тестами, иначе SQLite держит
  /// файл открытым и следующий прогон не может его пересоздать.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      '$dir/$databaseName',
      version: 3,
      onCreate: (d, v) async => _create(d),
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute('UPDATE photos SET rating = 6 WHERE rating = 1');
          await d.execute('UPDATE photos SET rating = 1 WHERE rating = -1');
        }
        if (oldV < 3) {
          await _addSortedColumn(d);
        }
      },
    );
  }

  Future<void> _addSortedColumn(Database d) async {
    await d.execute(
        'ALTER TABLE photos ADD COLUMN sorted INTEGER NOT NULL DEFAULT 0');
  }

  Future<void> _create(Database d) async {
    await d.execute('''
          CREATE TABLE photos (
            id TEXT PRIMARY KEY,
            rating INTEGER NOT NULL,
            day TEXT NOT NULL,
            rated_at INTEGER NOT NULL,
            deleted INTEGER NOT NULL DEFAULT 0,
            sorted INTEGER NOT NULL DEFAULT 0
          )
        ''');
    await d.execute('CREATE INDEX idx_photos_day ON photos(day)');
    await d.execute('CREATE INDEX idx_photos_rating ON photos(rating)');
    await d.execute('''
          CREATE TABLE sets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            day TEXT NOT NULL,
            asset_ids TEXT NOT NULL,
            cursor INTEGER NOT NULL DEFAULT 0,
            completed INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
  }

  @override
  Future<void> markSeen(String assetId, int rating) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final day = dayKey(DateTime.now());
    // UPDATE, а не REPLACE: переоценка не должна сбрасывать
    // флаги sorted/deleted, иначе фото снова попадёт в сортировку.
    final updated = await d.update(
      'photos',
      {'rating': rating, 'day': day, 'rated_at': now},
      where: 'id = ?',
      whereArgs: [assetId],
    );
    if (updated > 0) return;
    await d.insert(
      'photos',
      {
        'id': assetId,
        'rating': rating,
        'day': day,
        'rated_at': now,
        'deleted': 0,
        'sorted': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> clearRating(String assetId) async {
    final d = await db;
    // Строка удаляется целиком, а не обнуляется: с rating = 0 фото
    // считалось бы пропущенным, попадало в историю и статистику, а
    // «непросмотренным» больше не было. Удаление возвращает его в
    // исходное состояние — как будто оценки не было.
    await d.delete('photos', where: 'id = ?', whereArgs: [assetId]);
  }

  @override
  Future<Set<String>> seenIds() async {
    final d = await db;
    final rows = await d.query('photos', columns: ['id']);
    return rows.map((r) => r['id'] as String).toSet();
  }

  @override
  Future<List<PhotoRow>> rowsByRating(int rating) async {
    final d = await db;
    final rows = await d.query(
      'photos',
      where: 'rating = ? AND deleted = 0',
      whereArgs: [rating],
      orderBy: 'rated_at DESC',
    );
    return rows.map(PhotoRow.fromMap).toList();
  }

  @override
  Future<List<PhotoRow>> lowRatedRows() async {
    final d = await db;
    final rows = await d.query(
      'photos',
      where: 'rating BETWEEN 1 AND 5 AND deleted = 0',
      orderBy: 'rating ASC, rated_at DESC',
    );
    return rows.map(PhotoRow.fromMap).toList();
  }

  @override
  Future<Map<int, int>> ratingCounts() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT rating, COUNT(*) AS n FROM photos '
      "WHERE deleted = 0 AND rating BETWEEN 1 AND 10 "
      'GROUP BY rating',
    );
    final out = <int, int>{};
    for (final r in rows) {
      out[r['rating'] as int] = r['n'] as int;
    }
    return out;
  }

  @override
  Future<int> countByRating(int rating) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS n FROM photos WHERE deleted = 0 AND rating = ?',
      [rating],
    );
    final n = rows.isEmpty ? null : rows.first['n'];
    return (n as int?) ?? 0;
  }

  /// Сколько фото оценено и всё ещё находится в галерее.
  ///
  /// deleted = 0 важен для процента «галерея разобрана»: после удаления
  /// galleryTotal пересчитывается и уменьшается, а с deleted = 1 в числителе
  /// процент получался бы завышенным (вплоть до двукратного, если удалить
  /// половину оценённого).
  @override
  Future<int> totalSeen() async {
    final d = await db;
    return Sqflite.firstIntValue(
          await d.rawQuery('SELECT COUNT(*) FROM photos WHERE deleted = 0'),
        ) ??
        0;
  }

  @override
  Future<Map<String, DayStat>> dayStats() async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT day, rating, COUNT(*) AS n FROM photos '
      'WHERE deleted = 0 '
      'GROUP BY day, rating ORDER BY day DESC',
    );
    final map = <String, DayStat>{};
    for (final r in rows) {
      final day = r['day'] as String;
      final stat = map.putIfAbsent(day, () => DayStat(day: day));
      final n = r['n'] as int;
      final rating = r['rating'] as int;
      if (rating == 0) {
        stat.skips += n;
      } else if (rating >= 6) {
        stat.likes += n;
      } else {
        stat.dislikes += n;
      }
    }
    return map;
  }

  Future<List<PhotoRow>> rowsForDay(String day, {int limit = 30}) async {
    final d = await db;
    final rows = await d.query(
      'photos',
      where: 'day = ? AND rating != 0 AND deleted = 0',
      whereArgs: [day],
      orderBy: 'rated_at DESC',
      limit: limit,
    );
    return rows.map(PhotoRow.fromMap).toList();
  }

  @override
  Future<Map<String, List<PhotoRow>>> recentRowsPerDay(
      Iterable<String> days) async {
    final out = <String, List<PhotoRow>>{};
    for (final day in days) {
      out[day] = await rowsForDay(day);
    }
    return out;
  }

  @override
  Future<void> markDeleted(List<String> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    await d.update(
      'photos',
      {'deleted': 1},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  @override
  Future<List<PhotoRow>> unsortedRatedRows() async {
    final d = await db;
    final rows = await d.query(
      'photos',
      where: 'rating BETWEEN 1 AND 10 AND sorted = 0 AND deleted = 0',
      orderBy: 'rating DESC, rated_at DESC',
    );
    return rows.map(PhotoRow.fromMap).toList();
  }

  @override
  Future<void> markSorted(List<String> ids) async {
    if (ids.isEmpty) return;
    final d = await db;
    await d.update(
      'photos',
      {'sorted': 1},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  @override
  Future<int> unsortedCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery(
          'SELECT COUNT(*) FROM photos '
          'WHERE rating BETWEEN 1 AND 10 AND sorted = 0 AND deleted = 0',
        )) ??
        0;
  }

  @override
  Future<int> createSet(List<String> assetIds, String day) async {
    final d = await db;
    return d.insert('sets', {
      'day': day,
      'asset_ids': assetIds.join(','),
      'cursor': 0,
      'completed': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<SetInfo?> activeSet() async {
    final d = await db;
    final rows = await d.query('sets',
        where: 'completed = 0', orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return null;
    return SetInfo.fromMap(rows.first);
  }

  @override
  Future<void> advanceCursor(int setId, int cursor) async {
    final d = await db;
    await d.update('sets', {'cursor': cursor},
        where: 'id = ?', whereArgs: [setId]);
  }

  @override
  Future<void> completeSet(int setId) async {
    final d = await db;
    await d.update(
      'sets',
      {'completed': 1, 'cursor': -1},
      where: 'id = ?',
      whereArgs: [setId],
    );
  }

  /// Помечает все разложенные фото на повторную сортировку.
  @override
  Future<int> markAllUnsorted() async {
    final d = await db;
    return d.update('photos', {'sorted': 0},
        where: 'rating BETWEEN 1 AND 10 AND deleted = 0');
  }

  @override
  Future<int> sortedCount() async {
    final d = await db;
    return Sqflite.firstIntValue(await d.rawQuery(
          'SELECT COUNT(*) FROM photos WHERE rating BETWEEN 1 AND 10 AND sorted = 1 AND deleted = 0',
        )) ??
        0;
  }

  @override
  Future<void> resetAll() async {
    final d = await db;
    await d.delete('photos');
    await d.delete('sets');
  }

  /// Рейтинги сразу для набора ассетов — одним запросом.
  /// Ассеты без записи в таблице в результат не попадают.
  @override
  Future<Map<String, int>> ratingsForAssets(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final d = await db;
    final out = <String, int>{};
    // SQLite ограничивает количество параметров (~999), режем пачками.
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(
        i,
        i + 500 > ids.length ? ids.length : i + 500,
      );
      final rows = await d.query(
        'photos',
        columns: ['id', 'rating'],
        where: 'id IN (${List.filled(chunk.length, '?').join(',')})',
        whereArgs: chunk,
      );
      for (final r in rows) {
        out[r['id'] as String] = r['rating'] as int;
      }
    }
    return out;
  }

  /// Все оценки — для экспорта в JSON.
  @override
  Future<List<Map<String, Object?>>> allRatingMaps() async {
    final d = await db;
    return d.query('photos', orderBy: 'rated_at ASC');
  }

  Future<Set<String>> existingIds() async {
    final d = await db;
    final rows = await d.query('photos', columns: ['id']);
    return rows.map((r) => r['id'] as String).toSet();
  }

  /// Импорт оценок. Возвращает (добавлено, обновлено).
  /// Существующие записи обновляются без сброса sorted/deleted.
  @override
  Future<(int, int)> upsertRatings(List<Map<String, Object?>> rows) async {
    final d = await db;
    final existing = await existingIds();
    final batch = d.batch();
    var added = 0;
    var updated = 0;
    for (final r in rows) {
      final id = r['id'];
      final rating = r['rating'];
      if (id is! String || rating is! int) continue;
      if (rating < 0 || rating > 10) continue;
      final day = (r['day'] as String?) ?? dayKey(DateTime.now());
      final ratedAt =
          (r['rated_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch;
      if (existing.contains(id)) {
        batch.update(
          'photos',
          {'rating': rating, 'day': day, 'rated_at': ratedAt},
          where: 'id = ?',
          whereArgs: [id],
        );
        updated++;
      } else {
        batch.insert('photos', {
          'id': id,
          'rating': rating,
          'day': day,
          'rated_at': ratedAt,
          'deleted': 0,
          'sorted': 0,
        });
        added++;
      }
    }
    await batch.commit(noResult: true);
    return (added, updated);
  }

  @override
  Future<int> currentStreak() async {
    final d = await db;
    // Без фильтра rating != 0: день, в который пользователь только
    // промахивал, тоже активен — он же отнимал время и внимание.
    // С фильтром такие дни выпадали из серии и она обнулялась.
    final rows = await d.rawQuery(
      'SELECT DISTINCT day FROM photos ORDER BY day DESC LIMIT 366',
    );
    return computeStreak(
      rows.map((r) => r['day'] as String).toList(growable: false),
      DateTime.now(),
    );
  }

  /// Серия дней подряд, в которые пользователь хотя бы что-то оценил.
  ///
  /// Вынесено в чистую функцию ради тестируемости. Важная деталь:
  /// предыдущий день считаем через `DateTime(y, m, d - 1)`, а НЕ через
  /// `subtract(const Duration(days: 1))`. В сутках бывает 23 или 25 часов
  /// (перевод времени), и subtract от полуночи даёт 23:00 или 01:00
  /// предыдущего дня — сравнение с полуночью перестаёт работать и серия
  /// обнуляется дважды в год.
  static int computeStreak(List<String> activeDays, DateTime now) {
    if (activeDays.isEmpty) return 0;
    var expected = DateTime(now.year, now.month, now.day);
    var streak = 0;

    for (final iso in activeDays) {
      final p = iso.split('-');
      if (p.length != 3) continue;
      final y = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      final dd = int.tryParse(p[2]);
      if (y == null || m == null || dd == null) continue;
      final day = DateTime(y, m, dd);

      final isToday = _sameDay(day, expected);
      // Серия может начаться вчера: сегодняшнего дня ещё не было.
      final yesterday =
          DateTime(expected.year, expected.month, expected.day - 1);
      final isYesterday = streak == 0 && _sameDay(day, yesterday);

      if (isToday || isYesterday) {
        streak++;
        expected = DateTime(day.year, day.month, day.day - 1);
      } else {
        break;
      }
    }
    return streak;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String dayKey(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    return '${dt.year}-$m-$day';
  }
}
