import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/l10n.dart';
import '../core/notifications.dart';
import '../data/db.dart';
import '../data/gallery_service.dart';
import '../data/gallery_source.dart';
import '../data/models.dart';
import '../data/rating_store.dart';
import '../data/set_decision.dart';
import '../data/settings_repository.dart';

enum BootPhase { loading, needsOnboarding, needsPermission, ready }

class AppState extends ChangeNotifier {
  AppState({GallerySource? gallery, RatingStore? store})
      : _gallery = gallery ?? GalleryService.instance,
        _store = store ?? AppDb.instance;

  final RatingStore _store;
  final GallerySource _gallery;

  /// Галерея, с которой работает приложение. Экраны берут её отсюда,
  /// а не из статического синглтона: иначе удаление фото и копирование
  /// в папку нельзя подменить в тестах.
  GallerySource get gallery => _gallery;

  /// Хранилище оценок — по той же причине.
  RatingStore get store => _store;

  SettingsRepository? _settings;
  bool onboardedFlag = false;

  bool booted = false;
  BootPhase phase = BootPhase.loading;

  int dailyCount = 10;
  int appearMinutes = 20 * 60;
  ThemeMode themeMode = ThemeMode.system;
  String? localeCode;
  List<String> albumIds = [];

  SetInfo? activeSet;
  bool generating = false;
  bool poolEmpty = false;

  /// Сутки, на которых уже подтверждено «новых фото нет».
  /// Не даёт пересканировать галерею по минутному таймеру.
  String? poolEmptyDay;
  bool pruning = false;

  /// Идёт ли запись оценки в SQLite. Пока флаг поднят, повторный тап
  /// по той же карточке игнорируется.
  bool inFlightRating = false;

  int galleryTotal = 0;
  int seenTotal = 0;
  int currentStreak = 0;
  bool hasStreakLoaded = false;

  bool get hasAccess => _gallery.hasAccess;

  /// Ставит/снимает ежедневное напоминание под текущие настройки.
  /// Вызывается при init и любом изменении расписания.
  Future<void> syncNotification() async {
    if (!onboardedFlag) {
      await Notifications.instance.cancelDaily();
      return;
    }
    final body = L10n.fill(
      L10n.tr(localeCode, 'notifBody'),
      {'n': '$dailyCount'},
    );
    await Notifications.instance.scheduleDaily(
      minutes: appearMinutes,
      title: L10n.tr(localeCode, 'notifTitle'),
      body: body,
    );
  }

  Future<bool> requestNotificationPermission() async {
    final ok = await Notifications.instance.requestPermission();
    notifyListeners();
    return ok;
  }

  /// Запуск приложения. Не должна бросать: любое исключение здесь означает
  /// белый экран на старте и полностью недоступное приложение. Поэтому
  /// чтение настроек отделено от перехода по фазам — если хранилище
  /// недоступно, приложение всё равно покажет экран разрешения доступа,
  /// который пересоздаст настройки.
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _settings = SettingsRepository(prefs);

      onboardedFlag = _settings!.onboarded;
      dailyCount = _settings!.dailyCount;
      appearMinutes = _settings!.appearMinutes;
      themeMode = _settings!.themeMode;
      localeCode = _settings!.localeCode;
      albumIds = _settings!.albumIds;
    } catch (e) {
      debugPrint('[Gallerate] не удалось прочитать настройки: $e');
      _settings = null;
      onboardedFlag = false;
      phase = BootPhase.needsPermission;
      booted = true;
      notifyListeners();
      return;
    }

    booted = true;

    debugPrint('[Gallerate] init: onboarded=$onboardedFlag, phase=$phase');

    unawaited(syncNotification());

    if (!onboardedFlag) {
      phase = BootPhase.needsOnboarding;
      notifyListeners();
      return;
    }

    _gallery.setAccess(_settings?.permissionGranted ?? false);
    if (!_gallery.hasAccess) {
      phase = BootPhase.needsPermission;
      notifyListeners();
      return;
    }

    phase = BootPhase.ready;
    notifyListeners();
    unawaited(refreshCollections());
    await ensureTodaySet();
  }

  Future<bool> grantPermission() async {
    final ok = await _gallery.ensurePermission();
    await _settings?.setPermissionGranted(ok);
    if (ok) {
      if (onboardedFlag && phase == BootPhase.needsPermission) {
        phase = BootPhase.ready;
        unawaited(refreshCollections());
        await ensureTodaySet();
      }
      notifyListeners();
    }
    return ok;
  }

  /// Проверка разрешения при возврате в foreground: пользователь мог
  /// выдать доступ в системных настройках, пока приложение было в фоне.
  /// Если доступ уже есть, системный диалог не показывается, поэтому
  /// вызов безопасен и не спамит.
  Future<bool> recheckPermission() async {
    try {
      final state = await PhotoManager.requestPermissionExtend();
      final ok = state.hasAccess;
      if (ok == _gallery.hasAccess) return ok;
      _gallery.setAccess(ok);
      await _settings?.setPermissionGranted(ok);
      if (ok && onboardedFlag && phase == BootPhase.needsPermission) {
        phase = BootPhase.ready;
        unawaited(refreshCollections());
        await ensureTodaySet();
      }
      notifyListeners();
      return ok;
    } catch (e) {
      debugPrint('recheckPermission failed: $e');
      return _gallery.hasAccess;
    }
  }

  Future<void> openSystemSettings() => PhotoManager.openSetting();

  Future<void> refreshCollections() async {
    try {
      galleryTotal = await _gallery.totalCount(albumIds);
      seenTotal = await _store.totalSeen();
      currentStreak = await _store.currentStreak();
      hasStreakLoaded = true;
    } catch (e) {
      // Молча проглатывать нельзя: иначе «галерея разобрана на N%»
      // молча показывал бы 0% и не было бы видно, что счётчики не обновились.
      debugPrint('refreshCollections failed: $e');
    }
    notifyListeners();
  }

  int get curatedPercent {
    if (galleryTotal <= 0) return 0;
    return ((seenTotal / galleryTotal) * 100).round().clamp(0, 100);
  }

  bool _timeReached(DateTime now) =>
      now.hour * 60 + now.minute >= appearMinutes;

  String get appearTimeString {
    final h = (appearMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (appearMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> ensureTodaySet({bool force = false}) async {
    if (!_gallery.hasAccess || generating) return;
    final now = DateTime.now();
    final today = AppDb.dayKey(now);

    // Если сегодня уже известно, что новых фото не осталось — не сканируем
    // галерею снова. pickUnseen просматривает до 3000 ассетов в каждом
    // альбоме; без этой проверки минутный таймер в RootShell выжигал бы
    // батарею, пересканируя всю библиотеку каждую минуту.
    if (!force && poolEmpty && poolEmptyDay == today) return;

    generating = true;
    poolEmpty = false;
    notifyListeners();

    try {
      var set = await _store.activeSet();

      if (set != null && SetDecision.shouldCloseStaleSet(set.day, today)) {
        await _store.completeSet(set.id);
        set = null;
      }

      final mustGenerate = SetDecision.shouldGenerate(
        hasActiveSet: set != null,
        force: force,
        timeReached: _timeReached(now),
        poolEmpty: poolEmpty,
        poolEmptyDay: poolEmptyDay,
        today: today,
      );

      if (mustGenerate) {
        final exclude = await _store.seenIds();
        final picked = await _gallery.pickUnseen(
          count: dailyCount,
          excludeIds: exclude,
          selectedAlbumIds: albumIds.isEmpty ? null : albumIds,
        );
        if (picked.isEmpty) {
          poolEmpty = true;
          poolEmptyDay = today;
          activeSet = null;
          return;
        }
        final ids = picked.map((a) => a.id).toList(growable: false);
        final id = await _store.createSet(ids, today);
        poolEmptyDay = null;
        activeSet = SetInfo(
          id: id,
          day: today,
          assetIds: ids,
          cursor: 0,
          completed: false,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
      } else if (set != null) {
        activeSet = set;
      }
    } catch (e, st) {
      debugPrint('ensureTodaySet failed: $e\n$st');
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  Future<void> startExtraSet() => ensureTodaySet(force: true);

  /// Продвигает курсор, пока текущие ассеты недоступны (удалены/перемещены
  /// на устройстве). Без этого окно из 3 фото в SwipeScreen «съезжает»:
  /// assets[0] перестаёт совпадать с set.currentId и оценка уходит
  /// на другое фото.
  Future<void> pruneMissingAssets() async {
    final set = activeSet;
    if (set == null || !set.hasPending || pruning) return;
    pruning = true;
    try {
      // Проверка доступности уходит в нативный код, поэтому сначала
      // собираем флаги, а сам подсчёт отдаём чистой функции SetDecision.
      final availability = <bool>[];
      for (var i = set.cursor; i < set.assetIds.length; i++) {
        final asset = await AssetEntity.fromId(set.assetIds[i]);
        final isAvailable = asset != null;
        availability.add(isAvailable);
        // Дальше идти незачем: нас интересует только непрерывная серия
        // недоступных ассетов в начале.
        if (isAvailable) break;
      }

      final missing = SetDecision.countLeadingMissing(availability);
      if (missing == 0) return;

      final cursor = set.cursor + missing;
      if (cursor >= set.assetIds.length) {
        await _store.completeSet(set.id);
        activeSet = set.copyWith(cursor: cursor, completed: true);
      } else {
        await _store.advanceCursor(set.id, cursor);
        activeSet = set.copyWith(cursor: cursor);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('pruneMissingAssets failed: $e');
    } finally {
      pruning = false;
    }
  }

  Future<void> _applyRating(int rating) async {
    final set = activeSet;
    if (set == null || !set.hasPending) return;
    if (inFlightRating) return;
    final id = set.currentId!;

    // Защита от повторной оценки одной карточки. Анимация сброса длится
    // 320 мс, и пока _store.markSeen пишет в SQLite, второй тап по чипу
    // успевал пройти: он записывал ту же карточку заново (вторая оценка
    // перетирала первую), а курсор сдвигался всего на единицу — то есть
    // вторая оценка просто терялась.
    inFlightRating = true;
    try {
      await _store.markSeen(id, rating);
      final cursor = set.cursor + 1;
      final isSetFinished = cursor >= set.assetIds.length;
      if (isSetFinished) {
        await _store.completeSet(set.id);
        activeSet = set.copyWith(cursor: cursor, completed: true);
      } else {
        await _store.advanceCursor(set.id, cursor);
        activeSet = set.copyWith(cursor: cursor);
      }
      seenTotal += 1;
      // Серия пересчитывается при оценке и в конце сета. В конце — обязательно:
      // день, в который пользователь только промахивал (rating 0), тоже
      // считается активным в БД, но без пересчёта серия осталась бы прежней.
      if (rating > 0 || isSetFinished) {
        currentStreak = await _store.currentStreak();
        hasStreakLoaded = true;
      }
    } finally {
      inFlightRating = false;
    }
    notifyListeners();
  }

  Future<void> rateCurrent(int rating) => _applyRating(rating.clamp(0, 10));

  Future<void> skipCurrent() => _applyRating(0);

  /// Можно ли отменить последнюю оценку.
  ///
  /// Только пока набор открыт и в нём уже что-то оценено. Закрытый набор
  /// переоткрывать нельзя: экран сводки к нему уже привязан, и «отмена»
  /// превратилась бы в отдельный сценарий с двумя экранами.
  bool get canUndo {
    final set = activeSet;
    if (set == null) return false;
    if (set.completed) return false;
    return set.cursor > 0;
  }

  /// Отменить последнюю оценку: фото возвращается в колоду, оценка
  /// снимается, фото снова считается непросмотренным.
  ///
  /// Ошибку оценили — не должно быть способа исправить её только через
  /// списки «Лучшие» и «Убрать», куда надо специально идти.
  Future<void> undoLastRating() async {
    final set = activeSet;
    if (set == null || set.completed || set.cursor <= 0) return;
    if (inFlightRating) return;

    final index = set.cursor - 1;
    if (index < 0 || index >= set.assetIds.length) return;
    final id = set.assetIds[index];

    inFlightRating = true;
    try {
      await _store.clearRating(id);
      await _store.advanceCursor(set.id, index);
      activeSet = set.copyWith(cursor: index);
      if (seenTotal > 0) seenTotal -= 1;
      // Серия могла измениться: если отменённый день был единственным
      // активным, день перестаёт быть активным.
      currentStreak = await _store.currentStreak();
      hasStreakLoaded = true;
    } catch (e) {
      debugPrint('undoLastRating failed: $e');
    } finally {
      inFlightRating = false;
    }
    notifyListeners();
  }

  Future<void> setDailyCountAndSave(int v) async {
    dailyCount = v;
    await _settings?.setDailyCount(v);
    notifyListeners();
    await syncNotification();
  }

  Future<void> setAppearTime(TimeOfDay t) async {
    appearMinutes = t.hour * 60 + t.minute;
    await _settings?.setAppearMinutes(appearMinutes);
    notifyListeners();
    await syncNotification();
  }

  Future<void> setThemeModeAndSave(ThemeMode m) async {
    themeMode = m;
    await _settings?.setThemeMode(m);
    notifyListeners();
  }

  Future<void> setLocaleAndSave(String? code) async {
    localeCode = code;
    await _settings?.setLocaleCode(code);
    notifyListeners();
    await syncNotification();
  }

  Future<void> setAlbumsAndSave(List<String> ids) async {
    albumIds = ids;
    await _settings?.setAlbumIds(ids);
    // Набор альбомов изменился — прежний вывод «новых фото нет» больше
    // недействителен, иначе пользователь не увидит фото из нового альбома.
    _invalidatePool();
    notifyListeners();
    unawaited(refreshCollections());
  }

  void _invalidatePool() {
    poolEmpty = false;
    poolEmptyDay = null;
  }

  Future<void> finishOnboarding({
    required List<String> chosenAlbumIds,
    required int size,
    required TimeOfDay time,
  }) async {
    await setAlbumsAndSave(chosenAlbumIds);
    await setDailyCountAndSave(size);
    await setAppearTime(time);
    onboardedFlag = true;
    await _settings?.setOnboarded(true);
    phase = BootPhase.ready;
    notifyListeners();
    unawaited(refreshCollections());
    unawaited(syncNotification());
    await ensureTodaySet(force: true);
  }

  /// Переоценка уже оценённого фото. Раньше оценка была неизменяемой
  /// навсегда — ошибочный свайп нельзя было исправить.
  Future<void> rerate(String assetId, int rating) async {
    await _store.markSeen(assetId, rating.clamp(1, 10));
    await refreshCollections();
  }

  /// Очищает только оценки, сохраняя настройки и прохождение онбординга.
  Future<void> clearRatings() async {
    await _store.resetAll();
    activeSet = null;
    _invalidatePool();
    await refreshCollections();
    await ensureTodaySet(force: true);
  }

  /// Помечает разложенные фото на повторную сортировку.
  Future<int> markAllUnsorted() => _store.markAllUnsorted();

  Future<void> resetAll() async {
    await _store.resetAll();
    await _settings?.clearAll();
    await Notifications.instance.cancelDaily();
    _gallery.setAccess(false);
    activeSet = null;
    onboardedFlag = false;
    _invalidatePool();
    phase = BootPhase.needsOnboarding;
    dailyCount = 10;
    appearMinutes = 20 * 60;
    themeMode = ThemeMode.system;
    localeCode = null;
    albumIds = [];
    galleryTotal = 0;
    seenTotal = 0;
    notifyListeners();
  }
}
