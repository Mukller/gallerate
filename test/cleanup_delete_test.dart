import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/cleanup/cleanup_screen.dart';
import 'package:gallerate/ui/tab_index.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';
import 'support/photo_manager_mock.dart';

/// Удаление фото с устройства — самый разрушительный сценарий приложения.
///
/// Раньше он был принципиально непроверяем: экран звал статический
/// `GalleryService.instance`, нативный канал в тестах недоступен, и любой
/// тест удаления падал бы на попытке тронуть настоящую галерею.
/// Теперь галерея — внедряемая зависимость, и путь можно проверить целиком.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PhotoManagerMock.install();
    PhotoManagerMock.knownIds.clear();
  });

  tearDownAll(PhotoManagerMock.uninstall);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
  }

  late FakeRatingStore store;
  late FakeGallery gallery;
  late AppState app;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: Provider<int>.value(
          value: TabIndex.cleanup,
          child: MaterialApp(
            localizationsDelegates: const [
              DefaultMaterialLocalizations.delegate,
              DefaultWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('ru')],
            home: Scaffold(
              body: CleanupScreen(store: store, gallery: gallery),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  /// Выбирает фото в сетке — нижняя панель появляется только после этого.
  Future<void> selectPhoto(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('cleanup_photo_$id')));
    await tester.pump();
    await settle(tester);
  }

  /// Порядок фото в сетке слева направо, сверху вниз: по координатам,
  /// а не по номеру элемента — иначе проверка не отличила бы перестановку
  /// от смены содержимого. Сетка в три колонки, поэтому сравниваем
  /// сначала строку, потом столбец.
  List<String> orderOf(WidgetTester tester, List<String> ids) {
    final positioned = <({String id, double y, double x})>[];
    for (final id in ids) {
      final box = tester.getTopLeft(find.byKey(ValueKey('cleanup_photo_$id')));
      positioned.add((id: id, y: box.dy, x: box.dx));
    }
    positioned.sort((a, b) {
      final byRow = a.y.compareTo(b.y);
      return byRow != 0 ? byRow : a.x.compareTo(b.x);
    });
    return positioned.map((e) => e.id).toList();
  }

  setUp(() {
    store = FakeRatingStore();
    gallery = FakeGallery();
    app = AppState(gallery: gallery, store: store);
  });

  group('порядок очереди', () {
    testWidgets('по умолчанию — по оценке', (tester) async {
      await store.markSeen('bad1', 2);
      await store.markSeen('bad2', 5);

      await pump(tester);

      expect(find.text('By rating'), findsOneWidget);
      expect(find.text('By photo date, oldest first'), findsNothing);
    });

    testWidgets('переключатель меняет порядок на «по дате съёмки»',
        (tester) async {
      // Подобраны так, чтобы порядок по оценке и по дате различался:
      // bad1 — оценка 2 (хуже всех) и свежий снимок; bad2 — оценка 5 и
      // старый снимок. По оценке первым идёт bad1, по дате — bad2.
      await store.markSeen('bad1', 2, takenAt: 2000);
      await store.markSeen('bad2', 5, takenAt: 1000);
      await pump(tester);

      expect(find.text('By rating'), findsOneWidget);
      expect(orderOf(tester, ['bad1', 'bad2']), ['bad1', 'bad2'],
          reason: 'по оценке худший сверху');

      await tester.tap(find.byIcon(Icons.star_outline));
      await tester.pump();
      await settle(tester);

      expect(find.text('By photo date, oldest first'), findsOneWidget);
      expect(find.text('By rating'), findsNothing);
      expect(orderOf(tester, ['bad1', 'bad2']), ['bad2', 'bad1'],
          reason: 'по дате старый снимок сверху');
      expect(tester.takeException(), isNull);
    });

    testWidgets('переключение обратно возвращает «по оценке»', (tester) async {
      await store.markSeen('bad1', 2, takenAt: 1000);
      await pump(tester);

      await tester.tap(find.byIcon(Icons.star_outline));
      await tester.pump();
      await settle(tester);
      expect(find.text('By photo date, oldest first'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.event));
      await tester.pump();
      await settle(tester);

      expect(find.text('By rating'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('удаление из «Убрать»', () {
    testWidgets('фото с оценкой ниже 6 попадают в очередь', (tester) async {
      await store.markSeen('bad1', 2);
      await store.markSeen('bad2', 5);
      await store.markSeen('good1', 9);

      await pump(tester);

      expect(find.text('All clean!'), findsNothing);
      expect(find.byKey(const ValueKey('cleanup_photo_bad1')), findsOneWidget);
      expect(find.byKey(const ValueKey('cleanup_photo_good1')), findsNothing,
          reason: 'хорошие фото не попадают в очередь уборки');
      expect(gallery.deleteCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('нижняя панель появляется только после выбора фото',
        (tester) async {
      await store.markSeen('bad1', 2);
      await pump(tester);

      expect(find.textContaining('Delete selected'), findsNothing);

      await selectPhoto(tester, 'bad1');

      expect(find.textContaining('Delete selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('удаление просит подтверждения', (tester) async {
      await store.markSeen('bad1', 2);
      await pump(tester);

      await selectPhoto(tester, 'bad1');
      await tester.tap(find.textContaining('Delete selected'));
      await tester.pump();
      await settle(tester);

      // Диалог подтверждения показан, и ничего не удалено.
      expect(find.text('Delete from gallery?'), findsOneWidget);
      expect(gallery.deleteCalls, isEmpty,
          reason: 'до подтверждения ничего удалять нельзя');
    });

    testWidgets('отмена в диалоге ничего не удаляет', (tester) async {
      await store.markSeen('bad1', 2);
      await pump(tester);

      await selectPhoto(tester, 'bad1');
      await tester.tap(find.textContaining('Delete selected'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await settle(tester);

      expect(gallery.deleteCalls, isEmpty);
      expect(store.deletedOf('bad1'), isFalse,
          reason: 'фото должно остаться в очереди');
      expect(tester.takeException(), isNull);
    });

    testWidgets('подтверждение удаляет файлы и убирает фото из очереди',
        (tester) async {
      await store.markSeen('bad1', 2);
      await store.markSeen('bad2', 3);
      await pump(tester);

      await selectPhoto(tester, 'bad1');
      await tester.tap(find.text('Select all'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.textContaining('Delete selected'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.text('Delete')); // кнопка в диалоге
      await tester.pump();
      await settle(tester);

      // Файлы удалены с устройства — ровно те, что выбраны.
      expect(gallery.deleteCalls, hasLength(1));
      expect(gallery.deleteCalls.first.toSet(), {'bad1', 'bad2'});
      // И помечены удалёнными в базе.
      expect(store.deletedOf('bad1'), isTrue);
      expect(store.deletedOf('bad2'), isTrue);
      // Очередь пуста.
      expect(find.text('All clean!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('неудавшиеся фото остаются в очереди', (tester) async {
      await store.markSeen('bad1', 2);
      await store.markSeen('bad2', 3);
      // Система отказала в удалении одного файла.
      gallery.failDeleteIds = {'bad2'};
      await pump(tester);

      await selectPhoto(tester, 'bad1');
      await tester.tap(find.text('Select all'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.textContaining('Delete selected'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await settle(tester);

      // Удалённое — помечено, неудалённое — нет.
      expect(store.deletedOf('bad1'), isTrue);
      expect(store.deletedOf('bad2'), isFalse,
          reason: 'фото, которое не удалили, не должно считаться удалённым');
      // И оно осталось в очереди на следующий раз.
      expect(find.text('All clean!'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('сообщение сообщает, сколько удалили', (tester) async {
      await store.markSeen('bad1', 2);
      await store.markSeen('bad2', 3);
      await pump(tester);

      await selectPhoto(tester, 'bad1');
      await tester.tap(find.text('Select all'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.textContaining('Delete selected'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await settle(tester);

      expect(find.text('Deleted: 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('после удаления счётчик разобранной галереи уменьшается',
        (tester) async {
      await store.markSeen('bad1', 2);
      await store.markSeen('good1', 9);
      await app.refreshCollections();
      expect(app.seenTotal, 2);

      await pump(tester);
      await selectPhoto(tester, 'bad1');
      await tester.tap(find.textContaining('Delete selected'));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await settle(tester);

      expect(app.seenTotal, 1,
          reason: 'удалённое фото больше не считается разобранным');
      expect(tester.takeException(), isNull);
    });
  });
}
