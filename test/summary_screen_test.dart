import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/models.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/summary/summary_screen.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';

/// Сводка по завершённому набору.
///
/// Экран считает итоги по ассетам набора. Проверяем главное — математику:
/// пропуск не должен портить средний балл, а неоценённые фото не должны
/// попадать в «пропущено».
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

  SetInfo setOf(List<String> ids) => SetInfo(
        id: 1,
        day: '2026-09-28',
        assetIds: ids,
        cursor: ids.length,
        completed: true,
        createdAt: 1,
      );

  Widget host(AppState app, Widget child) {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ru')],
        home: child,
      ),
    );
  }

  group('Сводка: математика по набору', () {
    testWidgets('средний балл не учитывает пропуски', (tester) async {
      final store = FakeRatingStore();
      // 10 и 8 -> среднее 9.0; пропуск (0) в среднее не входит.
      await store.markSeen('a1', 10);
      await store.markSeen('a2', 8);
      await store.markSeen('a3', 0);
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(
        app,
        SummaryScreen(set: setOf(['a1', 'a2', 'a3']), store: store),
      ));
      await settle(tester);

      expect(find.text('9.0'), findsOneWidget);
      expect(find.text('2'), findsNWidgets(1), reason: 'оставлено = 2');
      expect(tester.takeException(), isNull);
    });

    testWidgets('оценка 5 идёт в «на удаление», а не в «оставлено»',
        (tester) async {
      final store = FakeRatingStore();
      await store.markSeen('a1', 10);
      await store.markSeen('a2', 6);
      await store.markSeen('a3', 5);
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(
        app,
        SummaryScreen(set: setOf(['a1', 'a2', 'a3']), store: store),
      ));
      await settle(tester);

      expect(store.ratingsForAssetsCalls, 1,
          reason: 'один запрос вместо N по числу ассетов');
      expect(find.text('3'), findsNWidgets(1), reason: 'всего оценено 3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('неоценённое фото не считается пропуском', (tester) async {
      final store = FakeRatingStore();
      // В наборе пять фото, оценено только одно.
      await store.markSeen('a1', 9);
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(
        app,
        SummaryScreen(
          set: setOf(['a1', 'a2', 'a3', 'a4', 'a5']),
          store: store,
        ),
      ));
      await settle(tester);

      // Пропущено ноль: у остальных фото просто нет оценки, это не пропуск.
      expect(store.ratingsForAssetsCalls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('пустой набор не падает и не делит на ноль', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(
        app,
        SummaryScreen(set: setOf([]), store: store),
      ));
      await settle(tester);

      // Среднего нет — прочерк вместо NaN.
      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('один запрос к базе на весь набор', (tester) async {
      final store = FakeRatingStore();
      for (var i = 0; i < 40; i++) {
        await store.markSeen('a$i', 7);
      }
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(
        app,
        SummaryScreen(
          set: setOf([for (var i = 0; i < 40; i++) 'a$i']),
          store: store,
        ),
      ));
      await settle(tester);

      // 40 ассетов — всё равно один запрос: набор может содержать 50.
      expect(store.ratingsForAssetsCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('Сводка: кнопки', () {
    testWidgets('заголовок и обе кнопки на месте', (tester) async {
      final store = FakeRatingStore();
      await store.markSeen('a1', 9);
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(
        app,
        SummaryScreen(set: setOf(['a1']), store: store),
      ));
      await settle(tester);

      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('показана доля разобранной галереи', (tester) async {
      final store = FakeRatingStore();
      await store.markSeen('a1', 9);
      await store.markSeen('a2', 8);
      // В галерее 4 фото, оценено 2 — ждём «2/4».
      final gallery = FakeGallery(photoCount: 4);
      final app = AppState(gallery: gallery, store: store);
      await app.refreshCollections();

      await tester.pumpWidget(host(
        app,
        SummaryScreen(set: setOf(['a1', 'a2']), store: store),
      ));
      await settle(tester);

      expect(find.text('2/4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
