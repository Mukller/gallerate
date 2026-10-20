import 'package:gallerate/data/gallery_source.dart';
import 'package:photo_manager/photo_manager.dart';

/// Фейковая галерея для тестов: отдаёт заранее заданные ассеты,
/// считает вызовы и позволяет проверить переданные параметры.
///
/// Нужна потому, что реальные `AssetEntity` создаёт нативный код, и
/// подменить `pickUnseen` на уровне канала нельзя — слишком много
/// внутренних деталей пакета.
class FakeGallery implements GallerySource {
  FakeGallery({
    this.access = true,
    this.albumCount = 3,
    this.photoCount = 40,
    List<String>? ids,
  }) : availableIds = ids ?? const [];

  bool access;
  final int albumCount;
  int photoCount;

  /// Идентификаторы, которые галерея отдаст в следующий раз.
  List<String> availableIds;

  /// Псевдоним для удобства в тестах: следующая выдача.
  List<String> get nextBatch => availableIds;
  set nextBatch(List<String> ids) => availableIds = ids;

  int pickCalls = 0;
  int totalCountCalls = 0;
  int permissionCalls = 0;
  List<String>? lastSelectedAlbums;
  int? lastRequestedCount;

  @override
  bool get hasAccess => access;

  @override
  void setAccess(bool v) => access = v;

  @override
  Future<bool> ensurePermission({bool openSettingsIfDenied = false}) async {
    permissionCalls++;
    return access;
  }

  @override
  Future<List<AssetPathEntity>> albums() async => List.generate(
        albumCount,
        (i) => AssetPathEntity(id: 'alb$i', name: 'Album $i'),
      );

  @override
  Future<int> totalCount(List<String>? selectedAlbumIds) async {
    totalCountCalls++;
    lastSelectedAlbums = selectedAlbumIds;
    return photoCount;
  }

  @override
  Future<List<AssetEntity>> pickUnseen({
    required int count,
    required Set<String> excludeIds,
    List<String>? selectedAlbumIds,
  }) async {
    pickCalls++;
    lastRequestedCount = count;
    lastSelectedAlbums = selectedAlbumIds;

    var budget = photoCount - excludeIds.length;
    final out = <AssetEntity>[];
    for (final id in availableIds) {
      if (out.length >= count || budget <= 0) break;
      if (excludeIds.contains(id)) continue;
      out.add(AssetEntity(id: id, typeInt: 1, width: 100, height: 100));
      budget--;
    }
    return out;
  }
}
