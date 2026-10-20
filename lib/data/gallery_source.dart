import 'package:photo_manager/photo_manager.dart';

/// Источник фото для приложения.
///
/// Сущности [AssetEntity] создаёт только нативный код photo_manager,
/// поэтому подменить канал в тестах почти невозможно: пришлось бы
/// воспроизводить структуру данных на стороне Android/iOS. Вместо этого
/// приложение работает через интерфейс, а реализация подменяется фейком
/// — так тестируется вся логика выбора сета без устройства.
abstract class GallerySource {
  /// Выдано ли разрешение на доступ к галерее.
  bool get hasAccess;

  /// Запрашивает разрешение. [openSettingsIfDenied] открывает системные
  /// настройки, если пользователь отказал.
  Future<bool> ensurePermission({bool openSettingsIfDenied = false});

  /// Восстанавливает известное состояние разрешения из настроек при старте,
  /// без показа системного диалога.
  void setAccess(bool v);

  /// Альбомы галереи.
  Future<List<AssetPathEntity>> albums();

  /// Сколько всего фото попадает под выбор альбомов.
  Future<int> totalCount(List<String>? selectedAlbumIds);

  /// Случайные неоценённые ассеты для нового сета.
  Future<List<AssetEntity>> pickUnseen({
    required int count,
    required Set<String> excludeIds,
    List<String>? selectedAlbumIds,
  });
}
