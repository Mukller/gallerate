import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_manager/photo_manager.dart';

/// Мок нативного канала photo_manager.
///
/// Нужен, чтобы `AssetEntity.fromId` работал в тестах. Реальные ассеты
/// создаёт нативный код, и без мока любой экран с фотографиями падал бы
/// либо не отрисовал сетку вовсе.
///
/// Формат ответа повторяет `ConvertUtils.convertMapToAsset`: обязательны
/// id / type / width / height, остальные поля опциональны. Миниатюры
/// намеренно не отдаём — приложение само ловит ошибку и рисует плейсхолдер.
class PhotoManagerMock {
  PhotoManagerMock._();

  static const MethodChannel _channel =
      MethodChannel('com.fluttercandies/photo_manager');

  /// Идентификаторы, которые канал считает существующими.
  static final Set<String> knownIds = {};

  /// Сколько раз просили разрешение.
  static int permissionCalls = 0;

  /// Сколько раз запрашивали свойства ассета.
  static int propertyCalls = 0;

  /// Разрешение выдано или нет.
  static bool permissionGranted = true;

  /// Альбомы, которые вернёт `getAssetPathList`.
  static List<({String id, String name})> albums = const [];

  static void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  static void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    knownIds.clear();
    albums = const [];
    permissionCalls = 0;
    propertyCalls = 0;
    permissionGranted = true;
  }

  static Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      // photo_manager ждёт int — индекс в PermissionState.values.
      case 'requestPermissionExtend':
      case 'getPermissionState':
        permissionCalls++;
        return permissionGranted
            ? _stateIndex('authorized')
            : _stateIndex('denied');

      case 'fetchEntityProperties':
        propertyCalls++;
        final args = call.arguments;
        final id = args is Map ? args['id'] as String? : null;
        if (id == null || !knownIds.contains(id)) return null;
        return <String, Object?>{
          'id': id,
          'type': 1, // AssetType.image
          'width': 100,
          'height': 100,
          'title': 'photo_$id.jpg',
          'createDt': 1700000000,
          'modified': 1700000000,
        };

      // Формат: Map с ключом 'data' -> List путей; у пути обязателен
      // assetCount, иначе он отбрасывается как пустой.
      case 'getAssetPathList':
        return <String, Object?>{
          'data': [
            for (final a in albums)
              <String, Object?>{
                'id': a.id,
                'name': a.name,
                'type': 1,
                'isAll': a.id == 'all',
                'assetCount': 1,
                'modified': 1700000000,
              },
          ],
        };

      case 'getAssetCountFromPath':
        return knownIds.length;

      case 'getAssetList':
      case 'getAssetListPaged':
        return <Object?>[];

      // Миниатюра недоступна: приложение обязано переживать это плейсхолдером.
      case 'getThumbnailDataWithSize':
      case 'getThumbnailWithSize':
        return null;

      default:
        // Неизвестные методы возвращаем null, а не бросаем: каждая
        // недостающая реализация не должна ронять тест.
        return null;
    }
  }

  /// Индекс состояния в `PermissionState.values`.
  static int _stateIndex(String name) {
    const values = PermissionState.values;
    final i = values.indexWhere((v) => v.name == name);
    if (i < 0) {
      throw StateError('неизвестное состояние разрешения: $name');
    }
    return i;
  }

  /// Ассет, который галерея считает существующим.
  static AssetEntity asset(String id) =>
      AssetEntity(id: id, typeInt: 1, width: 100, height: 100);
}
