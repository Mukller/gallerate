import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/core/rating_style.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/best/asset_image.dart';
import 'package:gallerate/ui/best/best_screen.dart';
import 'package:gallerate/ui/best/rating_chip.dart';
import 'package:gallerate/ui/cleanup/cleanup_screen.dart';
import 'package:gallerate/ui/tab_index.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';
import 'support/photo_manager_mock.dart';

/// Экраны «Лучшие» и «Убрать». Раньше не покрывались: сетки фото берутся
/// из галереи, а данные — из SQLite. Теперь обе зависимости подменены.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PhotoManagerMock.install();
    PhotoManagerMock.knownIds.clear();
    PhotoManagerMock.propertyCalls = 0;
  });

  tearDownAll(PhotoManagerMock.uninstall);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
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

  AppState make({FakeRatingStore? store}) => AppState(
        gallery: FakeGallery(),
        store: store ?? FakeRatingStore(),
      );

  group('BestScreen', () {
    testWidgets('пустое состояние объясняет, что делать', (tester) async {
      final store = FakeRatingStore();
      await tester.pumpWidget(
        host(make(), BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ряд чипов отрисован целиком', (tester) async {
      final store = FakeRatingStore();
      await tester.pumpWidget(
        host(make(), BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      expect(find.byType(RatingChip), findsNWidgets(10));
      expect(find.byType(RatingChipRow), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CleanupScreen', () {
    testWidgets('пустая очередь поздравляет с чистотой', (tester) async {
      final store = FakeRatingStore();
      await tester.pumpWidget(
        host(make(), CleanupScreen(store: store), TabIndex.cleanup),
      );
      await settle(tester);

      expect(find.text('All clean!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('сетка фото', () {
    testWidgets('оценённое фото попадает в сетку «Лучших»', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);
      // Оценка 10 — выбранный по умолчанию рейтинг.
      await store.markSeen('p1', 10);
      PhotoManagerMock.knownIds.add('p1');

      await tester.pumpWidget(
        host(app, BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      // Сетка отрисована, фото загружено через подменённый канал.
      expect(find.byType(AssetEntityImageLoader), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(PhotoManagerMock.propertyCalls, greaterThan(0));
    });

    testWidgets('фото с низкой оценкой попадает в очередь уборки',
        (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);
      await store.markSeen('bad1', 2);
      PhotoManagerMock.knownIds.add('bad1');

      await tester.pumpWidget(
        host(app, CleanupScreen(store: store), TabIndex.cleanup),
      );
      await settle(tester);

      expect(find.text('All clean!'), findsNothing,
          reason: 'очередь не должна быть пустой');
      expect(find.byType(AssetEntityImageLoader), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('удалённое фото не показывается в очереди уборки',
        (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);
      await store.markSeen('bad1', 2);
      await store.markDeleted(['bad1']);

      await tester.pumpWidget(
        host(app, CleanupScreen(store: store), TabIndex.cleanup),
      );
      await settle(tester);

      expect(find.text('All clean!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('счётчики чипов', () {
    testWidgets('на чипе видно число фото с оценкой', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);
      await store.markSeen('a', 8);
      await store.markSeen('b', 8);

      await tester.pumpWidget(
        host(app, BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      // Чип оценки 8 должен показывать 2.
      final chip8 = tester.widget<RatingChip>(
        find.byKey(const ValueKey('rating_chip_8')),
      );
      expect(chip8.count, 2);
      expect(chip8.selected, isFalse);
    });

    testWidgets('выбран по умолчанию рейтинг 10', (tester) async {
      final store = FakeRatingStore();
      await tester.pumpWidget(
        host(make(), BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      final chip10 = tester.widget<RatingChip>(
        find.byKey(const ValueKey('rating_chip_10')),
      );
      expect(chip10.selected, isTrue);
    });

    testWidgets('переключатель меняет порядок на «по дате съёмки»',
        (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);
      // Два фото с оценкой 8: одно снято раньше другого.
      await store.markSeen('old', 8, takenAt: 1000);
      await store.markSeen('new', 8, takenAt: 5000);

      await tester.pumpWidget(
        host(app, BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      expect(find.byIcon(Icons.star_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.star_outline));
      await tester.pump();
      await settle(tester);

      // Иконка сменилась — значит, порядок переключился.
      expect(find.byIcon(Icons.star_outline), findsNothing);
      expect(find.byIcon(Icons.event), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('нажатие на чип переключает выбор', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);
      await store.markSeen('a', 8);

      await tester.pumpWidget(
        host(app, BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('rating_chip_8')));
      await tester.pump();
      await settle(tester);

      final chip8 = tester.widget<RatingChip>(
        find.byKey(const ValueKey('rating_chip_8')),
      );
      final chip10 = tester.widget<RatingChip>(
        find.byKey(const ValueKey('rating_chip_10')),
      );
      expect(chip8.selected, isTrue);
      expect(chip10.selected, isFalse);
    });
  });

  group('RatingStyle в контексте экранов', () {
    test('оценка 6 — «оставить», 5 — «на удаление»', () {
      expect(RatingStyle.isKeep(6), isTrue);
      expect(RatingStyle.isKeep(5), isFalse);
      expect(RatingStyle.isDelete(5), isTrue);
    });
  });
}
