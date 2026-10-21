import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/swipe/card_deck.dart';
import 'package:gallerate/ui/summary/summary_screen.dart';
import 'package:gallerate/ui/swipe/photo_viewer.dart';
import 'package:gallerate/ui/swipe/swipe_screen.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';
import 'support/photo_manager_mock.dart';

/// Экран свайпа — главный экран приложения. Раньше не покрывался вовсе:
/// карточки берутся из галереи, ассеты создаёт нативный код, а хранилище
/// сидит на SQLite. Теперь канал галереи подменён (PhotoManagerMock), а
/// хранилище и галерея — фейками, поэтому экран проверяется целиком.
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

  Widget host(AppState app) {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: Provider<int>.value(
        value: 0, // вкладка «Свайп»
        child: const MaterialApp(
          localizationsDelegates: [
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          supportedLocales: [Locale('en'), Locale('ru')],
          home: Scaffold(body: SwipeScreen()),
        ),
      ),
    );
  }

  Future<AppState> stateWithSet(List<String> ids) async {
    final gallery = FakeGallery(ids: ids);
    final app = AppState(gallery: gallery, store: FakeRatingStore());
    app.dailyCount = ids.length;
    app.phase = BootPhase.ready;
    PhotoManagerMock.knownIds.addAll(ids);
    await app.ensureTodaySet(force: true);
    return app;
  }

  group('нет доступа', () {
    testWidgets('просит доступ и не показывает колоду', (tester) async {
      final app = AppState(
        gallery: FakeGallery(access: false),
        store: FakeRatingStore(),
      );
      app.phase = BootPhase.needsPermission;

      await tester.pumpWidget(host(app));
      await settle(tester);

      expect(find.text('Gallery access needed'), findsOneWidget);
      expect(find.text('Grant access'), findsOneWidget);
      expect(find.byType(SwipeCardDeck), findsNothing);
    });
  });

  group('набор готов', () {
    testWidgets('колода и прогресс 0 из N', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);

      await tester.pumpWidget(host(app));
      await settle(tester);

      expect(find.byType(SwipeCardDeck), findsOneWidget);
      expect(find.text('0 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('колода получает ассеты набора', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);

      await tester.pumpWidget(host(app));
      await settle(tester);

      final deck = tester.widget<SwipeCardDeck>(find.byType(SwipeCardDeck));
      expect(deck.assets.map((a) => a.id).toList(), ['a1', 'a2', 'a3']);
    });

    testWidgets('все чипы оценок и подсказка на месте', (tester) async {
      final app = await stateWithSet(['a1', 'a2']);

      await tester.pumpWidget(host(app));
      await settle(tester);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);
      expect(
        find.text('Swipe: right 6–10 · left 1–5 · further = stronger'),
        findsOneWidget,
      );
    });

// Чипы на экране: 1 и 10 показаны эмодзи (💩 и 🔥), остальные — числом.
    // Тест поймал две мои ошибки: чипа «7» в UI нет, а «1» и «10»
    // отображаются картинками, а не цифрами.
    testWidgets('доступные чипы оценок: 1, 3, 5, 6, 8, 10 и пропуск',
        (tester) async {
      final app = await stateWithSet(['a1', 'a2']);

      await tester.pumpWidget(host(app));
      await settle(tester);

      for (final r in ['3', '5', '6', '8']) {
        expect(find.text(r), findsOneWidget, reason: 'чип $r должен быть');
      }
      // Крайние оценки показаны эмодзи.
      expect(find.text('💩'), findsOneWidget, reason: 'оценка 1 = 💩');
      expect(find.text('🔥'), findsOneWidget, reason: 'оценка 10 = 🔥');

      // Чего в UI нет.
      expect(find.text('1'), findsNothing);
      expect(find.text('7'), findsNothing);
      expect(find.text('2'), findsNothing);
      expect(find.text('4'), findsNothing);
      expect(find.text('9'), findsNothing);
      expect(find.text('Skip'), findsOneWidget);
    });
  });

  group('оценка через чип', () {
    testWidgets('тап двигает курсор и счётчик', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      // Колода должна быть готова, иначе тап уйдёт в пустоту.
      expect(find.byType(SwipeCardDeck), findsOneWidget);
      final chip = find.text('8');
      expect(chip, findsOneWidget);
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      // Анимация вылета карточки — 320 мс. Кадров нужно с запасом,
      // иначе статус completed не успевает наступить и оценка не уйдёт.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);

      expect(app.activeSet!.cursor, 1);
      expect(app.activeSet!.currentId, 'a2');
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('после последней оценки колода исчезает', (tester) async {
      final app = await stateWithSet(['a1']);
      await tester.pumpWidget(host(app));
      await settle(tester);
      expect(find.byType(SwipeCardDeck), findsOneWidget);

      // Чипы на экране — 1, 3, 5 слева и 6, 8, 10 справа; «7» в UI нет,
// поэтому оценку ставим чипом, который реально есть.
      await tester.tap(find.text('6'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);

      expect(find.byType(SwipeCardDeck), findsNothing);
    });
  });

  group('отмена оценки', () {
    /// Прогоняет анимацию вылета карточки (320 мс).
    Future<void> flyOut(WidgetTester tester) async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
    }

    testWidgets('до первой оценки кнопки отмены нет', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);

      await tester.pumpWidget(host(app));
      await settle(tester);

      expect(find.byIcon(Icons.undo_rounded), findsNothing,
          reason: 'отменять нечего — кнопку показывать незачем');
    });

    testWidgets('после оценки кнопка появляется', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      await tester.tap(find.text('8'));
      await flyOut(tester);

      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
    });

    testWidgets('отмена возвращает фото в колоду', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      await tester.tap(find.text('8'));
      await flyOut(tester);
      expect(app.activeSet!.cursor, 1);
      expect(app.activeSet!.currentId, 'a2');

      await tester.tap(find.byIcon(Icons.undo_rounded));
      await flyOut(tester);

      expect(app.activeSet!.cursor, 0, reason: 'курсор вернулся назад');
      expect(app.activeSet!.currentId, 'a1');
      // Колода снова показывает отменённое фото.
      final deck = tester.widget<SwipeCardDeck>(find.byType(SwipeCardDeck));
      expect(deck.assets.first.id, 'a1');
      expect(find.text('0 / 3'), findsOneWidget);
    });

    testWidgets('после отмены кнопка прячется, когда отменять нечего',
        (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      await tester.tap(find.text('8'));
      await flyOut(tester);
      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.undo_rounded));
      await flyOut(tester);

      expect(find.byIcon(Icons.undo_rounded), findsNothing);
    });

    // Регрессия: оценка передаётся в момент завершения анимации вылета
    // (320 мс). Отмена в этот момент пересобирала набор, колода сбрасывала
    // состояние, и оценка пропадала молча: карточка улетела, в базе
    // ничего не записалось.
    testWidgets('отмена во время вылета карточки не съедает новую оценку',
        (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      // Первая оценка — чтобы появилась кнопка отмены.
      await tester.tap(find.text('8'));
      await flyOut(tester);
      expect(app.activeSet!.cursor, 1);

      // Вторая оценка: жмём чип и, пока карточка летит, жмём «отменить».
      await tester.tap(find.text('6'));
      await tester.pump(); // анимация только началась
      expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.undo_rounded));
      await flyOut(tester);

      // Оценка второй карточки обязана сохраниться: отмена была
      // отклонена, пока карточка летела.
      expect(app.activeSet!.cursor, 2,
          reason: 'оценка не должна пропасть из-за отмены в полёте');
      expect(app.activeSet!.currentId, 'a3');
      expect(tester.takeException(), isNull);
    });
  });

  group('карточка: дата и просмотр', () {
    testWidgets('на передней карточке показана дата снимка', (tester) async {
      final app = await stateWithSet(['a1', 'a2']);

      await tester.pumpWidget(host(app));
      await settle(tester);

      // Дата выводится в локальном времени — ожидание берём из того же
      // источника, что и мок, иначе тест зависел бы от часового пояса.
      expect(find.text(PhotoManagerMock.localDateOf('a1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('тап по фото открывает полноэкранный просмотр', (tester) async {
      final app = await stateWithSet(['a1', 'a2']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      expect(find.byType(PhotoViewerPage), findsNothing);

      await tester.tap(find.byType(SwipeCardDeck));
      await settle(tester);

      expect(find.byType(PhotoViewerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('тап по фото НЕ ставит оценку', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      await tester.tap(find.byType(SwipeCardDeck));
      await settle(tester);

      // Курсор на месте: тап — это просмотр, а не оценка.
      expect(app.activeSet!.cursor, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('просмотр закрывается тапом и оценка остаётся невыставленной',
        (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      await tester.tap(find.byType(SwipeCardDeck));
      await settle(tester);
      expect(find.byType(PhotoViewerPage), findsOneWidget);

      await tester.tapAt(const Offset(200, 200));
      await settle(tester);

      expect(find.byType(PhotoViewerPage), findsNothing);
      expect(app.activeSet!.cursor, 0);
      expect(tester.takeException(), isNull);
    });
  });

  group('набор закрыт', () {
    testWidgets('после сводки экран не остаётся с вечным спиннером',
        (tester) async {
      final app = await stateWithSet(['a1']);
      await tester.pumpWidget(host(app));
      await settle(tester);

      // Оцениваем единственное фото — набор закрывается, открывается сводка.
      await tester.tap(find.text('6'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      expect(find.byType(SummaryScreen), findsOneWidget);

      // Пользователь возвращается на главный экран (кнопка «Убрать»).
      Navigator.of(tester.element(find.byType(SummaryScreen))).pop();
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);

      // Экран должен быть пригодным: без вечного спиннера и с кнопкой.
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'после сводки главный экран не должен крутить спиннер');
      expect(find.text('That\'s the set for today'), findsOneWidget);
      expect(find.text('One more set'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('кнопка «ещё сет» создаёт новый набор', (tester) async {
      // В галерее два фото, а в наборе одно: после его прохождения остаётся
      // неоценённое фото, из которого можно собрать следующий набор.
      final gallery = FakeGallery(ids: ['a1', 'a2']);
      final app = AppState(gallery: gallery, store: FakeRatingStore());
      app.dailyCount = 1;
      app.phase = BootPhase.ready;
      PhotoManagerMock.knownIds.addAll(['a1', 'a2']);
      await app.ensureTodaySet(force: true);

      await tester.pumpWidget(host(app));
      await settle(tester);

      await tester.tap(find.text('6'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);
      Navigator.of(tester.element(find.byType(SummaryScreen))).pop();
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);

      await tester.tap(find.text('One more set'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await settle(tester);

      expect(app.activeSet, isNotNull);
      expect(app.activeSet!.hasPending, isTrue,
          reason: 'после «ещё сет» должен быть набор с фото');
      expect(tester.takeException(), isNull);
    });
  });

  group('ожидание и пустой пул', () {
    testWidgets('без набора показывается время появления', (tester) async {
      final app = AppState(
        gallery: FakeGallery(ids: const []),
        store: FakeRatingStore(),
      );
      app.phase = BootPhase.ready;

      await tester.pumpWidget(host(app));
      await settle(tester);

      expect(find.text('Set is not ready yet'), findsOneWidget);
      expect(find.text('Open now anyway'), findsOneWidget);
    });

    testWidgets('«открыть сейчас» создаёт набор', (tester) async {
      final gallery = FakeGallery(ids: ['x1', 'x2']);
      final app = AppState(gallery: gallery, store: FakeRatingStore());
      app.phase = BootPhase.ready;
      PhotoManagerMock.knownIds.addAll(['x1', 'x2']);

      await tester.pumpWidget(host(app));
      await settle(tester);

      await tester.tap(find.text('Open now anyway'));
      await tester.pump(const Duration(milliseconds: 50));
      await settle(tester);

      expect(app.activeSet, isNotNull);
      expect(gallery.pickCalls, 1);
      expect(find.byType(SwipeCardDeck), findsOneWidget);
    });

    testWidgets('пустой пул объясняется, а не выглядит как ошибка',
        (tester) async {
      final gallery = FakeGallery(photoCount: 0);
      final app = AppState(gallery: gallery, store: FakeRatingStore());
      app.phase = BootPhase.ready;
      await app.ensureTodaySet(force: true);

      await tester.pumpWidget(host(app));
      await settle(tester);

      expect(find.text('No new photos left'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ассет пропал с устройства', () {
    testWidgets('оценка не уходит на чужое фото', (tester) async {
      final app = await stateWithSet(['a1', 'a2', 'a3']);
      // Фото a1 удалили с устройства — канал его не знает.
      PhotoManagerMock.knownIds.remove('a1');

      await tester.pumpWidget(host(app));
      await tester.pump(const Duration(milliseconds: 50));
      await settle(tester);

      // Окно должно начинаться с доступного ассета, а не с пропавшего.
      final deck = tester.widgetList<SwipeCardDeck>(find.byType(SwipeCardDeck));
      expect(deck, isNotEmpty);
      if (deck.isNotEmpty) {
        expect(deck.first.assets.first.id, isNot('a1'));
      }
      expect(tester.takeException(), isNull);
    });
  });
}
