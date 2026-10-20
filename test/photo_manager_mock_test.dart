import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

import 'support/photo_manager_mock.dart';

/// Проверка самого мока: если он врёт, все виджет-тесты с фотографиями
/// будут проходить вхолостую, проверяя не то.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(PhotoManagerMock.uninstall);

  test('fromId отдаёт ассет для известного id', () async {
    PhotoManagerMock.install();
    PhotoManagerMock.knownIds.add('a1');

    final asset = await AssetEntity.fromId('a1');

    expect(asset, isNotNull);
    expect(asset!.id, 'a1');
    expect(asset.typeInt, 1);
    expect(asset.width, 100);
    expect(asset.height, 100);
    expect(asset.title, 'photo_a1.jpg');
  });

  test('fromId возвращает null для неизвестного id', () async {
    PhotoManagerMock.install();
    // knownIds пуст — ассета нет.

    final asset = await AssetEntity.fromId('нет-такого');

    expect(asset, isNull);
  });

  test('запрос разрешения возвращает выданное', () async {
    PhotoManagerMock.install();
    PhotoManagerMock.permissionGranted = true;

    expect((await PhotoManager.requestPermissionExtend()).hasAccess, isTrue);
    expect(PhotoManagerMock.permissionCalls, 1);
  });

  test('отказ в разрешении возвращает denied', () async {
    PhotoManagerMock.install();
    PhotoManagerMock.permissionGranted = false;

    expect((await PhotoManager.requestPermissionExtend()).hasAccess, isFalse);
  });

  test('альбомы читаются через getAssetPathList', () async {
    PhotoManagerMock.install();
    PhotoManagerMock.albums = const [(id: 'all', name: 'All')];

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
    );

    expect(paths.length, 1);
    expect(paths.first.id, 'all');
    expect(paths.first.name, 'All');
  });

  test('миниатюра недоступна — приложение должно это переживать', () async {
    PhotoManagerMock.install();
    final a = PhotoManagerMock.asset('a1');

    // Ошибка канала, а не исключение на стороне Dart.
    await expectLater(
      a.thumbnailDataWithSize(const ThumbnailSize(100, 100)),
      completion(isNull),
    );
  });
}
