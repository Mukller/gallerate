import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/models.dart';
import 'package:gallerate/logic/app_state.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';

/// Сквозные сценарии AppState на фейковых галерее и хранилище.
///
/// Раньше эти тесты гонялись по настоящему SQLite, но в виде��ет-тестах
/// sqflite не работает, а в обычных — зависимость от SQL мешала проверять
/// логику состояния. Теперь проверяются два уровня: этот (быстро, без SQL)
/// и db_test.dart (SQL на настоящей базе).
void main() {
  late FakeRatingStore store;
  late FakeGallery gallery;

  setUp(() {
    store = FakeRatingStore();
    gallery = FakeGallery();
  });

  AppState make() {
    final app = AppState(gallery: gallery, store: store);
    app.dailyCount = 10;
    app.phase = BootPhase.ready;
    return app;
  }

  /// AppState с готовым набором из [ids].
  Future<AppState> withSet(List<String> ids) async {
    final app = make();
    gallery.availableIds = ids;
    app.dailyCount = ids.length;
    await app.ensureTodaySet(force: true);
    return app;
  }

  group('доступ к галерее', () {
    test('без доступа сет не создаётся', () async {
      gallery.access = false;
      final app = make();

      await app.ensureTodaySet();

      expect(gallery.pickCalls, 0, reason: 'галерею не трогаем без доступа');
      expect(app.activeSet, isNull);
      expect(app.poolEmpty, isFalse);
    });
  });

  group('создание набора', () {
    test('force создаёт набор даже до времени появления', () async {
      gallery.availableIds = ['a1', 'a2', 'a3'];
      final app = make();
      app.dailyCount = 3;

      await app.ensureTodaySet(force: true);

      expect(gallery.pickCalls, 1);
      expect(app.activeSet, isNotNull);
      expect(app.activeSet!.assetIds, ['a1', 'a2', 'a3']);
      expect(app.activeSet!.cursor, 0);
      expect(app.activeSet!.completed, isFalse);
      expect(app.generating, isFalse);
    });

    test('размер набора берётся из настроек', () async {
      gallery.availableIds = ['a1', 'a2', 'a3', 'a4', 'a5', 'a6'];
      final app = make();
      app.dailyCount = 4;

      await app.ensureTodaySet(force: true);

      expect(gallery.lastRequestedCount, 4);
      expect(app.activeSet!.assetIds.length, 4);
    });

    test('пустая галерея помечает пул пустым', () async {
      gallery.photoCount = 0;
      final app = make();

      await app.ensureTodaySet(force: true);

      expect(gallery.pickCalls, 1);
      expect(app.activeSet, isNull);
      expect(app.poolEmpty, isTrue);
      expect(app.poolEmptyDay, isNotNull);
    });

    test('повторный вызов в тот же день не пересканирует галерею', () async {
      gallery.photoCount = 0;
      final app = make();

      await app.ensureTodaySet(force: true);
      expect(gallery.pickCalls, 1);

      // Минутный таймер в RootShell вызывает это постоянно.
      await app.ensureTodaySet();
      await app.ensureTodaySet();
      await app.ensureTodaySet();

      expect(gallery.pickCalls, 1,
          reason: 'пустой пул запомнен на сутки — батарея не выжигается');
    });

    test('force обходит память о пустом пуле', () async {
      gallery.photoCount = 0;
      final app = make();

      await app.ensureTodaySet(force: true);
      gallery
        ..availableIds = ['x1', 'x2']
        ..photoCount = 2;

      await app.ensureTodaySet(force: true);

      expect(gallery.pickCalls, 2);
      expect(app.activeSet, isNotNull);
      expect(app.poolEmpty, isFalse);
    });

    test('существующий незавершённый набор не пересоздаётся', () async {
      gallery.availableIds = ['a1', 'a2'];
      final app = make();
      app.dailyCount = 2;

      await app.ensureTodaySet(force: true);
      final firstId = app.activeSet!.id;

      await app.ensureTodaySet(force: true);

      expect(app.activeSet!.id, firstId);
      expect(gallery.pickCalls, 1,
          reason: 'активный набор нельзя подменять кнопкой «Ещё сет»');
    });

    test('вчерашний незакрытый набор закрывается, создаётся новый', () async {
      gallery.availableIds = ['y1', 'y2'];
      final app = make();
      app.dailyCount = 2;

      // Набор «за вчера» остался незакрытым.
      await store.createSet(['o1', 'o2'], '2026-01-01');

      await app.ensureTodaySet(force: true);

      expect(store.sets.length, 2);
      expect(store.sets.first.completed, isTrue);
      expect(app.activeSet!.id, store.sets.last.id);
    });

    test('выбранные альбомы передаются в галерею', () async {
      gallery.availableIds = ['a1'];
      final app = make();
      app.dailyCount = 1;
      app.albumIds = ['alb1'];

      await app.ensureTodaySet(force: true);

      expect(gallery.lastSelectedAlbums, ['alb1']);
    });

    test('без выбранных альбомов передаётся null', () async {
      gallery.availableIds = ['a1'];
      final app = make();
      app.dailyCount = 1;
      app.albumIds = const [];

      await app.ensureTodaySet(force: true);

      expect(gallery.lastSelectedAlbums, isNull,
          reason: 'пустой список = вся галерея');
    });
  });

  group('оценка и курсор', () {
    test('оценка двигает курсор и пишется в хранилище', () async {
      final app = await withSet(['a1', 'a2', 'a3']);

      await app.rateCurrent(8);

      expect(app.activeSet!.cursor, 1);
      expect(app.activeSet!.currentId, 'a2');
      expect(store.ratingOf('a1'), 8);
      expect(app.seenTotal, 1);
    });

    test('последняя оценка закрывает набор', () async {
      final app = await withSet(['a1', 'a2']);

      await app.rateCurrent(9);
      expect(app.activeSet!.completed, isFalse);

      await app.rateCurrent(6);
      expect(app.activeSet!.completed, isTrue);
      expect(app.activeSet!.hasPending, isFalse);
      expect(await store.activeSet(), isNull);
    });

    test('skip записывает 0 и тоже двигает курсор', () async {
      final app = await withSet(['a1', 'a2']);

      await app.skipCurrent();

      expect(store.ratingOf('a1'), 0);
      expect(app.activeSet!.cursor, 1);
    });

    test('оценка вне диапазона клампится', () async {
      final app = await withSet(['a1', 'a2']);

      await app.rateCurrent(99);

      expect(store.ratingOf('a1'), 10);
    });

    test('оценка без активного набора ничего не делает', () async {
      final app = make();

      await app.rateCurrent(5);

      expect(store.markSeenCalls, 0);
      expect(app.seenTotal, 0);
    });

    test('оценка закрытого набора ничего не делает', () async {
      final app = await withSet(['a1']);
      await app.rateCurrent(7);
      expect(app.activeSet!.completed, isTrue);
      final calls = store.markSeenCalls;

      await app.rateCurrent(7);

      expect(store.markSeenCalls, calls);
      expect(store.ratingOf('a1'), 7);
    });

    // Регрессия: пока идёт запись в хранилище, второй тап по той же
    // карточке успевал пройти и перетирал первую оценку, а курсор
    // сдвигался всего на единицу.
    test('повторный тап по той же карточке игнорируется', () async {
      final app = await withSet(['a1', 'a2', 'a3']);

      await Future.wait([app.rateCurrent(8), app.rateCurrent(2)]);

      expect(store.markSeenCalls, 1, reason: 'одна карточка = одна оценка');
      expect(app.activeSet!.cursor, 1);
    });

    test('оценка не сбрасывает признак «разложено»', () async {
      final app = await withSet(['a1', 'a2']);
      await app.rateCurrent(8);
      await store.markSorted(['a1']);

      await app.rateCurrent(3);

      expect(store.sortedOf('a1'), isTrue,
          reason: 'иначе фото снова попало бы в сортировку');
    });
  });

  group('серия дней', () {
    test('пересчитывается в конце набора даже без оценок', () async {
      store.activeDay = '2026-09-28';
      final app = await withSet(['a1']);

      await app.skipCurrent();

      expect(app.currentStreak, 1,
          reason: 'день с одним пропуском тоже активен');
      expect(app.hasStreakLoaded, isTrue);
    });

    test('после оценки серия равна единице', () async {
      store.activeDay = '2026-09-28';
      final app = await withSet(['a1', 'a2']);

      await app.rateCurrent(7);

      expect(app.currentStreak, 1);
    });
  });

  group('clearRatings и resetAll', () {
    test('clearRatings чистит оценки, но не настройки', () async {
      final app = await withSet(['a1', 'a2']);
      await app.rateCurrent(4);
      app.dailyCount = 2;

      await app.clearRatings();

      expect(app.dailyCount, 2, reason: 'настройки сохраняются');
      expect(app.activeSet, isNotNull, reason: 'набор пересоздан заново');
    });

    test('resetAll возвращает к онбордингу', () async {
      final app = await withSet(['a1']);
      gallery.access = true;

      await app.resetAll();

      expect(app.onboardedFlag, isFalse);
      expect(app.phase, BootPhase.needsOnboarding);
      expect(app.activeSet, isNull);
      expect(app.poolEmpty, isFalse);
      expect(gallery.access, isFalse);
    });

    test('resetAll стирает хранилище', () async {
      final app = await withSet(['a1']);
      await app.rateCurrent(5);

      await app.resetAll();

      expect(store.ratingOf('a1'), isNull);
      expect(store.sets, isEmpty);
    });
  });

  group('SetInfo в потоке приложения', () {
    test('hasPending корректен на всех позициях', () {
      SetInfo make(int cursor, {bool completed = false}) => SetInfo(
            id: 1,
            day: '2026-09-28',
            assetIds: ['a1', 'a2', 'a3'],
            cursor: cursor,
            completed: completed,
            createdAt: 0,
          );

      expect(make(0).hasPending, isTrue);
      expect(make(2).hasPending, isTrue);
      expect(make(3).hasPending, isFalse);
      expect(make(0, completed: true).hasPending, isFalse);
      expect(make(-1).hasPending, isFalse);
      expect(make(0).currentId, 'a1');
      expect(make(3).currentId, isNull);
    });
  });
}
