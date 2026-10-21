import 'package:gallerate/data/models.dart';
import 'package:gallerate/data/rating_store.dart';

/// Хранилище в памяти для тестов.
///
/// Нужно потому, что `sqflite_common_ffi` не работает внутри
/// виджет-тестов Flutter: операции БД не завершаются в fake-async зоне и
/// тест зависает намертво. Настоящий SQLite при этом проверяется отдельно
/// обычными тестами (см. db_test.dart), так что оба уровня закрыты.
class FakeRatingStore implements RatingStore {
  /// id -> (оценка, удалён, разложен, день оценки, дата съёмки)
  final Map<String,
          ({int rating, bool deleted, bool sorted, String day, int? takenAt})>
      _photos = {};

  final List<SetInfo> _sets = [];

  /// День, который считается активным (для currentStreak).
  String? activeDay;

  /// День, который проставляется фото без явного дня. Тесты, которым
  /// нужно разложить оценки по дням, задают [dayOf] при пометке.
  String defaultDay = '2026-09-28';

  int _nextSetId = 1;

  // Счётчики вызовов — чтобы проверять, что лишних обращений нет.
  int markSeenCalls = 0;
  int seenIdsCalls = 0;
  int activeSetCalls = 0;
  int dayStatsCalls = 0;
  int recentRowsPerDayCalls = 0;
  int ratingCountsCalls = 0;
  int countByRatingCalls = 0;
  int ratingsForAssetsCalls = 0;
  int allRatingMapsCalls = 0;
  int upsertRatingsCalls = 0;

  /// Пометить фото оценкой конкретного дня.
  Future<void> markSeenOn(String assetId, int rating, String day) =>
      _mark(assetId, rating, day: day);

  @override
  Future<void> markSeen(String assetId, int rating, {int? takenAt}) =>
      _mark(assetId, rating, day: defaultDay, takenAt: takenAt);

  Future<void> _mark(
    String assetId,
    int rating, {
    required String day,
    int? takenAt,
  }) async {
    markSeenCalls++;
    // Тот же контракт, что у боевой базы: недопустимая оценка —
    // ошибка вызывающего кода, а не «тихое» значение в данных.
    if (!isValidRating(rating)) {
      throw ArgumentError.value(rating, 'rating', 'оценка вне диапазона 0..10');
    }
    final prev = _photos[assetId];
    _photos[assetId] = (
      rating: rating,
      // Оценка не должна сбрасывать признаки «удалено» и «разложено».
      deleted: prev?.deleted ?? false,
      sorted: prev?.sorted ?? false,
      // День перезаписывается, как в боевой БД: переоценка переносит
      // фото в сегодняшний день истории. Фейк раньше сохранял старый
      // день и тем самым скрывал расхождение с production.
      day: day,
      // Дата съёмки дописывается, только если её прислали: как и в базе,
      // неизвестная дата не должна затираться null-ом при переоценке.
      takenAt: takenAt ?? prev?.takenAt,
    );
  }

  @override
  Future<Set<String>> seenIds() async {
    seenIdsCalls++;
    return _photos.keys.toSet();
  }

  @override
  Future<int> totalSeen() async =>
      _photos.values.where((p) => !p.deleted).length;

  @override
  Future<int> currentStreak() async => activeDay == null ? 0 : 1;

  @override
  Future<void> markDeleted(List<String> ids) async {
    for (final id in ids) {
      final p = _photos[id];
      if (p == null) continue;
      _photos[id] = (
        rating: p.rating,
        deleted: true,
        sorted: p.sorted,
        day: p.day,
        takenAt: p.takenAt,
      );
    }
  }

  @override
  Future<void> markSorted(List<String> ids) async {
    for (final id in ids) {
      final p = _photos[id];
      if (p == null) continue;
      _photos[id] = (
        rating: p.rating,
        deleted: p.deleted,
        sorted: true,
        day: p.day,
        takenAt: p.takenAt,
      );
    }
  }

  @override
  Future<int> unsortedCount() async => _photos.values
      .where((p) => !p.deleted && !p.sorted && p.rating >= 1 && p.rating <= 10)
      .length;

  @override
  Future<int> sortedCount() async =>
      _photos.values.where((p) => !p.deleted && p.sorted).length;

  @override
  Future<int> markAllUnsorted() async {
    var n = 0;
    for (final entry in _photos.entries.toList()) {
      if (!entry.value.sorted) continue;
      _photos[entry.key] = (
        rating: entry.value.rating,
        deleted: entry.value.deleted,
        sorted: false,
        day: entry.value.day,
        takenAt: entry.value.takenAt,
      );
      n++;
    }
    return n;
  }

  @override
  Future<void> resetAll() async {
    _photos.clear();
    _sets.clear();
    _nextSetId = 1;
  }

  @override
  Future<int> createSet(List<String> assetIds, String day) async {
    final id = _nextSetId++;
    _sets.add(SetInfo(
      id: id,
      day: day,
      assetIds: assetIds,
      cursor: 0,
      completed: false,
      createdAt: id,
    ));
    return id;
  }

  @override
  Future<SetInfo?> activeSet() async {
    activeSetCalls++;
    for (final s in _sets.reversed) {
      if (!s.completed) return s;
    }
    return null;
  }

  @override
  Future<void> advanceCursor(int setId, int cursor) async {
    _replaceCursor(setId, cursor);
  }

  @override
  Future<void> completeSet(int setId) async {
    final i = _sets.indexWhere((s) => s.id == setId);
    if (i < 0) return;
    _sets[i] = _sets[i].copyWith(cursor: -1, completed: true);
  }

  void _replaceCursor(int setId, int cursor) {
    final i = _sets.indexWhere((s) => s.id == setId);
    if (i < 0) return;
    _sets[i] = _sets[i].copyWith(cursor: cursor);
  }

  /// Оценка для проверок.
  int? ratingOf(String id) => _photos[id]?.rating;

  bool? sortedOf(String id) => _photos[id]?.sorted;

  bool? deletedOf(String id) => _photos[id]?.deleted;

  /// Наборы для проверок.
  List<SetInfo> get sets => List.unmodifiable(_sets);

  List<PhotoRow> get _rows => [
        for (final e in _photos.entries)
          if (!e.value.deleted && e.value.rating >= 1 && e.value.rating <= 10)
            PhotoRow(
              id: e.key,
              rating: e.value.rating,
              day: e.value.day,
              ratedAt: 1,
              deleted: e.value.deleted,
              sorted: e.value.sorted,
              takenAt: e.value.takenAt,
            ),
      ];

  /// Счётчик фото по каждой оценке.
  @override
  Future<Map<int, int>> ratingCounts() async {
    ratingCountsCalls++;
    final out = <int, int>{};
    for (final p in _photos.values) {
      if (p.deleted || p.rating < 1 || p.rating > 10) continue;
      out[p.rating] = (out[p.rating] ?? 0) + 1;
    }
    return out;
  }

  /// Рейтинги для сводки набора.
  @override
  Future<Map<String, int>> ratingsForAssets(List<String> ids) async {
    ratingsForAssetsCalls++;
    final out = <String, int>{};
    for (final id in ids) {
      final p = _photos[id];
      if (p != null && !p.deleted) out[id] = p.rating;
    }
    return out;
  }

  /// Когда задано — хранилище падает с этой ошибкой на чтении.
  /// Нужно, чтобы проверить, что экраны показывают сообщение об ошибке,
  /// а не вечный спиннер: раньше FutureBuilder не различал «грузится»
  /// и «упало».
  Object? failWith;

  /// Сколько фото с конкретной оценкой (0 = пропуск).
  @override
  Future<int> countByRating(int rating) async {
    countByRatingCalls++;
    var n = 0;
    for (final p in _photos.values) {
      if (!p.deleted && p.rating == rating) n++;
    }
    return n;
  }

  /// Сводка по дням: оставлено (6..10), на удаление (1..5), пропущено (0).
  @override
  Future<Map<String, DayStat>> dayStats() async {
    dayStatsCalls++;
    if (failWith != null) throw failWith!;
    final out = <String, DayStat>{};
    for (final e in _photos.entries) {
      final p = e.value;
      if (p.deleted) continue;
      final s = out.putIfAbsent(p.day, () => DayStat(day: p.day));
      if (p.rating == 0) {
        s.skips++;
      } else if (p.rating >= 6) {
        s.likes++;
      } else {
        s.dislikes++;
      }
    }
    return out;
  }

  /// Недавние фото по дням.
  @override
  Future<Map<String, List<PhotoRow>>> recentRowsPerDay(
    List<String> days,
  ) async {
    recentRowsPerDayCalls++;
    final out = <String, List<PhotoRow>>{};
    for (final day in days) {
      out[day] = _rows.where((r) => r.day == day).toList();
    }
    return out;
  }

  /// Снять оценку: запись удаляется целиком, как в SQLite.
  @override
  Future<void> clearRating(String assetId) async {
    _photos.remove(assetId);
  }

  /// Экспорт: сырые строки, как в SQLite.
  @override
  Future<List<Map<String, Object?>>> allRatingMaps() async {
    allRatingMapsCalls++;
    // Набор колонок совпадает с боевой БД: экспорт из фейка иначе не
    // похож на настоящий, и round-trip через фейк терял данные.
    return [
      for (final e in _photos.entries)
        {
          'id': e.key,
          'rating': e.value.rating,
          'day': e.value.day,
          'rated_at': 1,
          'deleted': e.value.deleted ? 1 : 0,
          'sorted': e.value.sorted ? 1 : 0,
          'taken_at': e.value.takenAt,
        }
    ];
  }

  /// Импорт: (добавлено, обновлено).
  ///
  /// Повторяет поведение боевой БД: диапазон оценки проверяется, а
  /// флаги и дата съёмки переносятся. Иначе фейк принимал то, что
  /// production отбрасывал, и тесты проверяли не тот путь.
  @override
  Future<(int, int)> upsertRatings(List<Map<String, Object?>> rows) async {
    upsertRatingsCalls++;
    var added = 0;
    var updated = 0;
    for (final r in rows) {
      final id = r['id'];
      final rating = r['rating'];
      if (id is! String || rating is! int) continue;
      if (rating < 0 || rating > 10) continue;
      final prev = _photos[id];
      final day = r['day'] as String? ?? defaultDay;
      final takenAt = r['taken_at'] as int?;
      _photos[id] = (
        rating: rating,
        deleted: (r['deleted'] as int? ?? 0) == 1,
        sorted: (r['sorted'] as int? ?? 0) == 1,
        day: day,
        takenAt: takenAt ?? prev?.takenAt,
      );
      if (prev == null) {
        added++;
      } else {
        updated++;
      }
    }
    return (added, updated);
  }

  /// Фото с конкретной оценкой.
  @override
  Future<List<PhotoRow>> rowsByRating(
    int rating, {
    PhotoSort sort = PhotoSort.rating,
  }) async {
    if (failWith != null) throw failWith!;
    final rows = _rows.where((r) => r.rating == rating).toList();
    return _sorted(rows, sort,
        byRating: (a, b) => b.ratedAt.compareTo(a.ratedAt));
  }

  /// Фото с низкими оценками — очередь уборки.
  @override
  Future<List<PhotoRow>> lowRatedRows({
    PhotoSort sort = PhotoSort.rating,
  }) async {
    if (failWith != null) throw failWith!;
    final rows = _rows.where((r) => r.rating >= 1 && r.rating <= 5).toList();
    return _sorted(rows, sort, byRating: (a, b) {
      final byRating = a.rating.compareTo(b.rating);
      return byRating != 0 ? byRating : b.ratedAt.compareTo(a.ratedAt);
    });
  }

  /// Порядок выдачи — тот же, что в базе: фото с неизвестной датой съёмки
  /// в конец, остальные от старых к новым.
  List<PhotoRow> _sorted(
    List<PhotoRow> rows,
    PhotoSort sort, {
    required int Function(PhotoRow, PhotoRow) byRating,
  }) {
    switch (sort) {
      case PhotoSort.rating:
        rows.sort(byRating);
      case PhotoSort.takenDate:
        rows.sort((a, b) {
          final at = a.takenAt;
          final bt = b.takenAt;
          if (at == null && bt == null) return byRating(a, b);
          if (at == null) return 1; // неизвестная дата — в конец
          if (bt == null) return -1;
          final byDate = at.compareTo(bt);
          return byDate != 0 ? byDate : byRating(a, b);
        });
    }
    return rows;
  }

  /// Оценённые фото, ещё не разложенные.
  @override
  Future<List<PhotoRow>> unsortedRatedRows() async {
    final rows = _rows.where((r) => r.sorted == false).toList()
      ..sort((a, b) {
        final byRating = b.rating.compareTo(a.rating);
        return byRating != 0 ? byRating : b.ratedAt.compareTo(a.ratedAt);
      });
    return rows;
  }
}
