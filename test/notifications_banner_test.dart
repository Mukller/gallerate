import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

import 'support/fake_gallery.dart';
import 'support/fake_rating_store.dart';

/// Уведомления выключены — пользователь должен об этом знать.
///
/// Раньше отказ в разрешении на уведомления был полностью молчаливым:
/// время напоминания сохранялось, выглядело настроенным, а напоминание
/// не приходило. Ключи `notifPermTitle`/`notifPermBody` лежали в словаре
/// и не использовались нигде.
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

  Widget host(AppState app) {
    return ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        localizationsDelegates: const [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ru')],
        home: Scaffold(body: SettingsScreen(store: app.store)),
      ),
    );
  }

  testWidgets('при выключенных уведомлениях показано предупреждение',
      (tester) async {
    final app = AppState(gallery: FakeGallery(), store: FakeRatingStore());
    app.notificationsOff = true;

    await tester.pumpWidget(host(app));
    await settle(tester);

    expect(find.text('Reminders are off'), findsOneWidget);
    expect(find.text('Allow notifications'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('при включённых уведомлениях предупреждения нет', (tester) async {
    final app = AppState(gallery: FakeGallery(), store: FakeRatingStore());
    app.notificationsOff = false;

    await tester.pumpWidget(host(app));
    await settle(tester);

    expect(find.text('Reminders are off'), findsNothing);
    expect(find.text('Allow notifications'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
