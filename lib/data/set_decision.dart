/// Чистые правила работы с дневным сетом.
///
/// Вынесено из AppState без зависимостей специально ради тестируемости:
/// логика «вчерашний сет / новый день / пустой пул / не пора» — самая
/// рискованная часть приложения, и раньше она не была покрыта ни одним
/// тестом, потому что была зашита в метод с обращениями к БД и галерее.
class SetDecision {
  SetDecision._();

  /// Сутки, которые нужно закрыть: вчерашний незавершённый сет при наступлении
  /// нового дня.
  ///
  /// [setDay] — день существующего набора, [today] — текущий.
  static bool shouldCloseStaleSet(String? setDay, String today) {
    if (setDay == null) return false;
    if (setDay == today) return false;
    // Завершённые наборы в БД отбираются как completed = 0, но подстрахуемся.
    return true;
  }

  /// Нужно ли генерировать новый набор прямо сейчас.
  ///
  /// - [hasActiveSet] — есть ли незавершённый набор;
  /// - [force] — пользователь нажал «Открыть сейчас» / «Ещё сет»;
  /// - [timeReached] — наступило ли время появления сета;
  /// - [poolEmpty] / [poolEmptyDay] — сегодня уже подтверждено, что новых
  ///   фото нет (защита от пересканирования галереи по таймеру).
  static bool shouldGenerate({
    required bool hasActiveSet,
    required bool force,
    required bool timeReached,
    required bool poolEmpty,
    required String? poolEmptyDay,
    required String today,
  }) {
    if (hasActiveSet) return false;
    if (force) return true;
    // Новые фото уже кончились сегодня — повторно не сканируем галерею.
    if (poolEmpty && poolEmptyDay == today) return false;
    return timeReached;
  }

  /// Пора ли показывать пользователю экран ожидания, а не пустой экран.
  static bool isWaitingForSetTime({required bool timeReached}) => !timeReached;

  /// Сколько ассетов в начале сета недоступно (удалены или перемещены).
  ///
  /// Нужно, чтобы окно из трёх фото в SwipeScreen не «съезжало»: если
  /// текущий асет пропал, assets[0] перестаёт совпадать с currentId и
  /// оценка уходит на чужое фото. Пропускаем недоступные, пока не дойдём
  /// до первого существующего.
  ///
  /// [available] — флаги доступности, вычисленные асинхронно вызывающей
  /// стороной (проверка ассета уходит в нативный код, поэтому она не может
  /// быть частью этой чистой функции).
  static int countLeadingMissing(List<bool> available) {
    var missing = 0;
    for (final isAvailable in available) {
      if (isAvailable) break;
      missing++;
    }
    return missing;
  }
}
