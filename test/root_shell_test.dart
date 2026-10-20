import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/root_shell.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';

/// Оболочка приложения: пять вкладок в [IndexedStack], минутный таймер и
/// реакция на возврат из фона.
///
/// Здесь важна не отрисовка, а то, что приложение **не делает работу впустую**
/// и **не пропускает момент появления набора**: сет генерировался только при
/// старте, и если пользователь держал приложение открытым через час
/// появления, набор не появлялся до перезапуска.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
  }

  Widget host(AppState app, FakeRatingStore store) {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ru')],
        home: RootShell(store: store),
      ),
    );
  }

  group('Оболочка: вкладки', () {
    testWidgets('пять вкладок и по умолчанию открыт «Свайп»', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(app, store));
      await settle(tester);

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
      expect(bar.destinations, hasLength(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('тап по вкладке переключает заголовок', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(app, store));
      await settle(tester);

      // Четвёртая вкладка — «История».
      await tester.tap(find.byIcon(Icons.history_outlined));
      await tester.pump();
      await settle(tester);

      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('возврат на предыдущую вкладку не сбрасывает её данные',
        (tester) async {
      final store = FakeRatingStore();
      await store.markSeenOn('a1', 9, '2026-09-28');
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(app, store));
      await settle(tester);

      // Открываем «Историю» — экран читает базу.
      await tester.tap(find.byIcon(Icons.history_outlined));
      await tester.pump();
      await settle(tester);
      final afterOpen = store.dayStatsCalls;
      expect(afterOpen, greaterThan(0));

      // Уходим на «Свайп» и возвращаемся: данные уже загружены.
      await tester.tap(find.byIcon(Icons.style_outlined));
      await tester.pump();
      await settle(tester);
      await tester.tap(find.byIcon(Icons.history_outlined));
      await tester.pump();
      await settle(tester);

      expect(store.dayStatsCalls, afterOpen,
          reason: 'экран живёт в IndexedStack, состояние не пересоздаётся');
    });
  });
  group('Оболочка: возврат из фона', () {
    testWidgets('на resumed набор досоздаётся', (tester) async {
      final gallery = FakeGallery(ids: const []);
      final store = FakeRatingStore();
      final app = AppState(gallery: gallery, store: store);

      // Момент появления ещё не наступил. Ставим заведомо будущее время,
      // чтобы результат НЕ зависел от настенных часов: иначе тест падает
      // после 20:00 и проходит до 20:00.
      app.appearMinutes = 24 * 60;

      await tester.pumpWidget(host(app, store));
      await settle(tester);
      // Набор ещё не создан — время не пришло.
      expect(store.sets, isEmpty);

      // Появились фото, и пользователь вернулся из фона в момент, когда
      // набор уже должен был появиться.
      gallery.availableIds = const ['x1', 'x2'];
      app.appearMinutes = 0;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(gallery.pickCalls, greaterThan(0),
          reason: 'после возврата в фон галерея должна быть пересканирована');
      expect(store.sets, hasLength(1),
          reason: 'набор должен появиться без перезапуска приложения');
      expect(store.sets.single.assetIds, ['x1', 'x2']);
    });

    testWidgets('пустой пул не пересканируется до следующего дня',
        (tester) async {
      final gallery = FakeGallery(ids: const []);
      final store = FakeRatingStore();
      final app = AppState(gallery: gallery, store: store);
      app.appearMinutes = 0;

      await tester.pumpWidget(host(app, store));
      await settle(tester);

      // Галерея пуста — приложение должно один раз проверить её и запомнить,
      // что новых фото нет.
      await app.ensureTodaySet();
      await settle(tester);
      final callsAfterFirst = gallery.pickCalls;
      expect(callsAfterFirst, greaterThan(0));

      // Минутный таймер не должен каждый раз пересканировать библиотеку:
      // pickUnseen просматривает до 3000 ассетов в каждом альбоме.
      for (var i = 0; i < 3; i++) {
        await app.ensureTodaySet();
      }
      await settle(tester);

      expect(gallery.pickCalls, callsAfterFirst,
          reason: 'пустой пул отмечен на сегодня — повторных сканов быть не '
              'должно, иначе минутный таймер выжигал бы батарею');
    });

    testWidgets('удаление экрана останавливает таймер', (tester) async {
      final store = FakeRatingStore();
      final app = AppState(gallery: FakeGallery(), store: store);

      await tester.pumpWidget(host(app, store));
      await settle(tester);

      // Заменяем оболочку — dispose обязан отменить минутный таймер,
      // иначе он продолжит будить приложение после закрытия.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await settle(tester);

      expect(tester.takeException(), isNull);
    });
  });
}
