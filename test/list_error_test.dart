import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/best/best_screen.dart';
import 'package:gallerate/ui/cleanup/cleanup_screen.dart';
import 'package:gallerate/ui/history/history_screen.dart';
import 'package:gallerate/ui/list_error_view.dart';
import 'package:gallerate/ui/stats/stats_screen.dart';
import 'package:gallerate/ui/tab_index.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';

/// Ошибка загрузки данных на экранах со списками.
///
/// Раньше `FutureBuilder` не различал «ещё грузится» и «упало с
/// ошибкой»: при ошибке `hasData` тоже ложно, и экран навсегда
/// оставался с вращающимся индикатором — без текста и без кнопки
/// повторить. Пользователь не мог понять, сломалось приложение или
/// данных просто нет.
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

  late FakeRatingStore store;
  late AppState app;

  setUp(() {
    store = FakeRatingStore();
    app = AppState(gallery: FakeGallery(), store: store);
  });

  group('ошибка загрузки', () {
    testWidgets('«Убрать» показывает ошибку, а не спиннер', (tester) async {
      store.failWith = StateError('db is locked');

      await tester.pumpWidget(
        host(app, CleanupScreen(store: store), TabIndex.cleanup),
      );
      await settle(tester);

      expect(find.byType(ListErrorView), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Лучшие» показывает ошибку, а не спиннер', (tester) async {
      store.failWith = StateError('db is locked');

      await tester.pumpWidget(
        host(app, BestScreen(store: store), TabIndex.best),
      );
      await settle(tester);

      expect(find.byType(ListErrorView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«История» показывает ошибку, а не спиннер', (tester) async {
      store.failWith = StateError('db is locked');

      await tester.pumpWidget(
        host(app, HistoryScreen(store: store), TabIndex.history),
      );
      await settle(tester);

      expect(find.byType(ListErrorView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Статистика» показывает ошибку, а не спиннер', (tester) async {
      store.failWith = StateError('db is locked');

      await tester.pumpWidget(
        host(app, StatsScreen(store: store), TabIndex.stats),
      );
      await settle(tester);

      expect(find.byType(ListErrorView), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('кнопка «повторить» перечитывает данные', (tester) async {
      store.failWith = StateError('db is locked');

      await tester.pumpWidget(
        host(app, CleanupScreen(store: store), TabIndex.cleanup),
      );
      await settle(tester);
      expect(find.byType(ListErrorView), findsOneWidget);

      // База ожила — повтор должен показать данные.
      store.failWith = null;
      await store.markSeen('bad1', 2);

      await tester.tap(find.text('Try again'));
      await tester.pump();
      await settle(tester);

      expect(find.byType(ListErrorView), findsNothing);
      expect(find.byKey(const ValueKey('cleanup_photo_bad1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
