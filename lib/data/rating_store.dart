import 'models.dart';

/// Хранилище оценок и наборов.
///
/// Вынесено в интерфейс по практической причине: `sqflite_common_ffi`
/// не работает внутри виджет-тестов Flutter (операции БД не завершаются
/// в fake-async зоне и тест зависает). С интерфейсом экраны можно
/// проверять виджет-тестами, подставляя хранилище в памяти, а настоящий
/// SQLite проверять отдельно обычными тестами — так покрыты оба уровня.
abstract class RatingStore {
  /// Записать оценку ассета. Повторная оценка не должна сбрасывать
  /// признаки «разложено» и «удалено».
  ///
  /// [takenAt] — когда сделан снимок (мс с эпохи). Необязателен: без него
  /// дата съёмки неизвестна, и фото не сможет попасть в сортировку
  /// по возрасту.
  Future<void> markSeen(String assetId, int rating, {int? takenAt});

  /// Идентификаторы всех ассетов, которым уже выставлена оценка.
  Future<Set<String>> seenIds();

  /// Сколько ассетов оценено и ещё не удалено.
  Future<int> totalSeen();

  /// Текущая серия дней подряд.
  Future<int> currentStreak();

  /// Пометить ассеты удалёнными из галереи.
  Future<void> markDeleted(List<String> ids);

  /// Пометить ассеты разложенными по альбомам.
  Future<void> markSorted(List<String> ids);

  /// Сколько ассетов ждут раскладки.
  Future<int> unsortedCount();

  /// Сколько ассетов уже разложено.
  Future<int> sortedCount();

  /// Снять признак «разложено» со всех — для повторной сортировки.
  Future<int> markAllUnsorted();

  /// Очистить всё: оценки и наборы.
  Future<void> resetAll();

  /// Создать набор на сегодняшний день.
  Future<int> createSet(List<String> assetIds, String day);

  /// Последний незавершённый набор, либо null.
  Future<SetInfo?> activeSet();

  /// Сдвинуть курсор набора.
  Future<void> advanceCursor(int setId, int cursor);

  /// Закрыть набор.
  Future<void> completeSet(int setId);

  /// Счётчик фото по каждой оценке (1..10).
  Future<Map<int, int>> ratingCounts();

  /// Фото с конкретной оценкой.
  Future<List<PhotoRow>> rowsByRating(int rating,
      {PhotoSort sort = PhotoSort.rating});

  /// Фото с низкими оценками — очередь уборки.
  Future<List<PhotoRow>> lowRatedRows({PhotoSort sort = PhotoSort.rating});

  /// Оценённые фото, ещё не разложенные по альбомам.
  Future<List<PhotoRow>> unsortedRatedRows();

  /// Фото, которым выставлена конкретная оценка (для сводки набора).
  Future<Map<String, int>> ratingsForAssets(List<String> ids);

  /// Сколько неудалённых фото имеют конкретную оценку.
  /// rating = 0 — это пропуск.
  Future<int> countByRating(int rating);

  /// Сводка по дням: сколько оставлено, удалено и пропущено.
  Future<Map<String, DayStat>> dayStats();

  /// Недавние фото, сгруппированные по дням (для экрана истории).
  Future<Map<String, List<PhotoRow>>> recentRowsPerDay(List<String> days);

  /// Все оценки в виде сырых строк — для экспорта в JSON.
  Future<List<Map<String, Object?>>> allRatingMaps();

  /// Загрузить оценки из JSON: (добавлено, обновлено).
  Future<(int, int)> upsertRatings(List<Map<String, Object?>> rows);

  /// Снять оценку с ассета: запись удаляется целиком.
  ///
  /// Нужна для отмены оценки. Фото снова становится «непросмотренным»
  /// и может попасть в следующий набор, а из истории и статистики оно
  /// исчезает — как будто оценки не было.
  Future<void> clearRating(String assetId);
}
