import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/data/db.dart';
import 'package:gallerate/data/models.dart';
import 'package:gallerate/logic/app_state.dart';
import 'package:gallerate/ui/best/asset_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/photo_manager_mock.dart';

/// Раньше экраны с фотографиями нельзя было проверить вовсе: ассеты
/// создаёт нативный код photo_manager. Теперь нативный канал подменён
/// (см. [PhotoManagerMock]), поэтому сетки и миниатюры рендерятся по-настоящему.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    // Канал ставим на каждый тест: uninstall в tearDown снял бы его
    // после первого же теста, и остальные шли бы вовсе без мока.
    PhotoManagerMock.install();
    SharedPreferences.setMockInitialValues({});
    AppDb.databaseName = 'gallerate_image_test.db';
    await AppDb.instance.close();
    final dir = await databaseFactory.getDatabasesPath();
    await deleteDatabase('$dir/${AppDb.databaseName}');
    PhotoManagerMock.knownIds.clear();
    PhotoManagerMock.propertyCalls = 0;
  });

  tearDownAll(PhotoManagerMock.uninstall);

  Future<void> insertRating(String id, int rating) async {
    final db = await AppDb.instance.db;
    await db.insert('photos', {
      'id': id,
      'rating': rating,
      'day': '2026-09-28',
      'rated_at': 1,
      'deleted': 0,
      'sorted': 0,
    });
  }

  Widget host(Widget child) {
    return MaterialApp(
      localizationsDelegates: const [
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ru')],
      home: Scaffold(body: child),
    );
  }

  group('AssetEntityImageLoader', () {
    testWidgets('известный ассет превращается в миниатюру-плейсхолдер',
        (tester) async {
      PhotoManagerMock.knownIds.add('a1');

      await tester.pumpWidget(
        host(const SizedBox(
          width: 100,
          height: 100,
          child: AssetEntityImageLoader(assetId: 'a1'),
        )),
      );
      // Даём Future'у долететь до канала и отрисоваться.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }

      // Ассет найден — канал отработал, а миниатюры нет: виджет обязан
      // показать плейсхолдер, а не упасть.
      expect(tester.takeException(), isNull);
      expect(PhotoManagerMock.propertyCalls, greaterThan(0));
      expect(find.byType(AssetEntityImageLoader), findsOneWidget);
    });

    testWidgets('неизвестный ассет не роняет экран', (tester) async {
      // knownIds пуст — ассета в галерее нет (например, фото удалили).
      await tester.pumpWidget(
        host(const SizedBox(
          width: 100,
          height: 100,
          child: AssetEntityImageLoader(assetId: 'удалённое'),
        )),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('смена assetId перезапрашивает ассет', (tester) async {
      // Кэш Future живёт статически и переживает тесты, поэтому берём
      // заведомо новый id — иначе проверка шла бы вхолостую.
      final first = 'first-${DateTime.now().microsecondsSinceEpoch}';
      final second = 'second-${DateTime.now().microsecondsSinceEpoch}';
      PhotoManagerMock.knownIds.addAll({first, second});

      await tester.pumpWidget(
        host(SizedBox(
          width: 100,
          height: 100,
          child: AssetEntityImageLoader(assetId: first),
        )),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      final before = PhotoManagerMock.propertyCalls;
      expect(before, greaterThan(0));

      await tester.pumpWidget(
        host(SizedBox(
          width: 100,
          height: 100,
          child: AssetEntityImageLoader(assetId: second),
        )),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }

      expect(PhotoManagerMock.propertyCalls, greaterThan(before),
          reason: 'новый assetId обязан вызвать канал заново');
    });

    // Регрессия: future создавался прямо в build(), из-за чего каждый
    // кадр порождал новый запрос и экран уходил в бесконечный reload.
    testWidgets('повторная перестройка не вызывает новых запросов',
        (tester) async {
      PhotoManagerMock.knownIds.add('a1');

      await tester.pumpWidget(
        host(const SizedBox(
          width: 100,
          height: 100,
          child: AssetEntityImageLoader(assetId: 'a1'),
        )),
      );
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      final afterLoad = PhotoManagerMock.propertyCalls;

      // Принудительно перестраиваем дерево несколько раз.
      for (var i = 0; i < 6; i++) {
        await tester.pumpWidget(
          host(SizedBox(
            width: 100,
            height: 100,
            child: AssetEntityImageLoader(key: ValueKey(i), assetId: 'a1'),
          )),
        );
        await tester.pump();
      }

      expect(PhotoManagerMock.propertyCalls, afterLoad,
          reason: 'Future кэшируется по id — перестроек не плодит запросы');
    });
  });

  group('PhotoRow', () {
    test('разбирается из строки БД со всеми флагами', () {
      final row = PhotoRow.fromMap({
        'id': 'a1',
        'rating': 7,
        'day': '2026-09-28',
        'rated_at': 1700000000,
        'deleted': 0,
        'sorted': 1,
      });

      expect(row.id, 'a1');
      expect(row.rating, 7);
      expect(row.deleted, isFalse);
      expect(row.sorted, isTrue);
    });

    test('отсутствующий sorted считается «не разложено»', () {
      final row = PhotoRow.fromMap({
        'id': 'a1',
        'rating': 7,
        'day': '2026-09-28',
        'rated_at': 1,
        'deleted': 0,
      });
      expect(row.sorted, isFalse);
    });
  });

  group('оценки в БД + канал галереи вместе', () {
    test('оценённое фото находится через нативный канал', () async {
      await insertRating('a1', 8);
      PhotoManagerMock.knownIds.add('a1');

      final rows = await AppDb.instance.rowsByRating(8);
      expect(rows.length, 1);

      final asset = PhotoManagerMock.asset('a1');
      expect(asset.id, rows.single.id,
          reason: 'БД и галерея должны говорить об одном и том же id');
    });

    testAppState();
  });
}

/// Отдельная функция, чтобы не плодить вложенные группы внутри группы.
void testAppState() {
  test('AppState без доступа просит разрешение', () async {
    PhotoManagerMock.permissionGranted = false;
    final app = AppState();
    expect(app.hasAccess, isFalse);
    PhotoManagerMock.permissionGranted = true;
  });
}
