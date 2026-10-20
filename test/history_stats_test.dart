import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/history/history_screen.dart';
import 'package:gallerate/ui/stats/stats_screen.dart';
import 'package:gallerate/ui/tab_index.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';

/// История и статистика.
///
/// Главное здесь — не «экран нарисовался», а **сколько раз он ходит в базу**.
/// Экраны живут в `IndexedStack` и строятся все сразу при запуске, когда их
/// вкладки ещё не выбраны. Если грузить данные в `initState`, сводка по всем
/// дням считается при каждом старте приложения для невидимого экрана.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
  }

  Widget host(AppState app, Widget child, int tab) {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: Provider<int>.value(
        value: tab,
        child: MaterialApp(
          localizationsDelegates: const [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('ru')],
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  Future<FakeRatingStore> filled() async {
    final store = FakeRatingStore();
    // Два дня активности: 28-е и 29-е сентября.
    await store.markSeenOn('a1', 10, '2026-09-28');
    await store.markSeenOn('a2', 8, '2026-09-28');
    await store.markSeenOn('a3', 2, '2026-09-28');
    await store.markSeenOn('b1', 7, '2026-09-29');
    await store.markSeenOn('b2', 0, '2026-09-29');
    return store;
  }

  group('История: база не трогается, пока вкладку не открыли', () {
    testWidgets('на невидимой вкладке запросов к базе нет', (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      // Вкладка 0 — свайп, история не выбрана.
      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.swipe),
      );
      await settle(tester);

      expect(store.dayStatsCalls, 0,
          reason: 'невидимый экран не должен считать сводку по дням');
      expect(store.recentRowsPerDayCalls, 0);
      // И спиннера быть не должно: данных ещё не запрашивали.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('при открытии вкладки база читается ровно один раз',
        (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.swipe),
      );
      await settle(tester);

      // Пользователь переключился на «Историю».
      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);

      expect(store.dayStatsCalls, 1, reason: 'одна загрузка при открытии');
      expect(store.recentRowsPerDayCalls, 1);
    });

    testWidgets('повторный показ без изменений не перечитывает базу',
        (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);
      expect(store.dayStatsCalls, 1);

      // Уходим на другую вкладку и возвращаемся — оценок не добавляли.
      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.swipe),
      );
      await settle(tester);
      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);

      expect(store.dayStatsCalls, 1,
          reason: 'данные не менялись — повторный запрос не нужен');
    });

    testWidgets('новая оценка перечитывает базу', (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);
      expect(store.dayStatsCalls, 1);

      // Пользователь оценил ещё одно фото на соседней вкладке.
      await store.markSeenOn('c1', 9, '2026-09-29');
      await app.refreshCollections();

      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);

      expect(store.dayStatsCalls, 2,
          reason: 'после новой оценки сводка обязана обновиться');
    });
  });

  group('История: содержимое', () {
    testWidgets('день выводится в привычном формате', (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);

      // 2026-09-28 -> 28.09.2026, свежий день первым.
      expect(find.text('28.09.2026'), findsOneWidget);
      expect(find.text('29.09.2026'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('пустая история объясняет, что делать', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);

      // Ключ historyEmpty принадлежит экрану истории; у статистики свой.
      expect(find.text('Your daily rating history will appear here.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Статистика: та же дисциплина загрузки', () {
    testWidgets('на невидимой вкладке запросов к базе нет', (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, StatsScreen(store: store), TabIndex.swipe),
      );
      await settle(tester);

      expect(store.ratingCountsCalls, 0);
      expect(store.dayStatsCalls, 0);
      expect(store.countByRatingCalls, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('при открытии читает базу ровно один раз', (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, StatsScreen(store: store), TabIndex.swipe),
      );
      await settle(tester);
      await tester.pumpWidget(
        host(app, StatsScreen(store: store), TabIndex.stats),
      );
      await settle(tester);

      expect(store.ratingCountsCalls, 1);
      expect(store.dayStatsCalls, 1);
      expect(store.countByRatingCalls, 1);
    });

    testWidgets('считает оставленные и удаляемые по разным сторонам',
        (tester) async {
      final store = await filled();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, StatsScreen(store: store), TabIndex.stats),
      );
      await settle(tester);

      // Оставлено: 10, 8, 7 = 3. На удаление: 2 = 1. Пропущено: 0 = 1.
      // Всего оценено 5 (пропуск тоже оценка).
      expect(find.text('5'), findsOneWidget, reason: 'всего оценено');
      expect(find.text('Keep · 3'), findsOneWidget);
      expect(find.text('Remove · 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('пустая статистика не рисует пустую круговую диаграмму',
        (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, StatsScreen(store: store), TabIndex.stats),
      );
      await settle(tester);

      // Круговая диаграмма с пустым sections бросила бы исключение.
      expect(find.text('Nothing rated yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('удалённое фото не попадает в итоги', (tester) async {
      final store = await filled();
      // Перед подсчётом удаляем одно из «оставленных».
      await store.markDeleted(['a1']);
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(
        host(app, StatsScreen(store: store), TabIndex.stats),
      );
      await settle(tester);

      // Осталось: 8, 7 = 2 оставлено, 2 = 1 удаляемое, пропуск 1.
      expect(find.text('Keep · 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
