import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

import 'gallery_source.dart';

class GalleryService implements GallerySource {
  GalleryService._();

  static final GalleryService instance = GalleryService._();

  bool _hasAccess = false;

  /// Предохранитель на объём сканирования одного альбома.
  /// 50 000 ≈ 250 страниц по 200 — достаточно, чтобы не упереться в
  /// потолок на реальных галереях, и достаточно мало, чтобы не зависнуть.
  static const int _maxScanPerAlbum = 50000;

  @override
  bool get hasAccess => _hasAccess;

  @override
  Future<bool> ensurePermission({bool openSettingsIfDenied = false}) async {
    final state = await PhotoManager.requestPermissionExtend();
    if (!state.hasAccess && openSettingsIfDenied) {
      await PhotoManager.openSetting();
      final again = await PhotoManager.requestPermissionExtend();
      _hasAccess = again.hasAccess;
      return _hasAccess;
    }
    _hasAccess = state.hasAccess;
    return _hasAccess;
  }

  @override
  void setAccess(bool v) => _hasAccess = v;

  @override
  Future<List<AssetPathEntity>> albums() async {
    if (!_hasAccess) return [];
    return PhotoManager.getAssetPathList(type: RequestType.common);
  }

  /// Сколько всего фото попадает под выбор альбомов.
  ///
  /// Альбомы пересекаются: на Android «Все фото» содержит то же, что
  /// «Камера», «Скриншоты» и т.д. Наивная сумма assetCountAsync по всем
  /// альбомам завышает total в разы, и «галерея разобрана на N%» показывала
  /// бы неверный процент. Поэтому при пустом выборе (вся галерея) берём
  /// альбом, помеченный как isAll, а не складываем всё.
  @override
  Future<int> totalCount(List<String>? selectedIds) async {
    final paths = await albums();
    if (selectedIds == null || selectedIds.isEmpty) {
      for (final p in paths) {
        if (p.isAll) return await p.assetCountAsync;
      }
    }
    final chosen = _choose(paths, selectedIds);
    var total = 0;
    for (final p in chosen) {
      if (p.isAll) return await p.assetCountAsync;
      total += await p.assetCountAsync;
    }
    return total;
  }

  @override
  Future<List<AssetEntity>> pickUnseen({
    required int count,
    required Set<String> excludeIds,
    List<String>? selectedAlbumIds,
  }) async {
    final paths = await albums();
    final chosen = _chooseForScan(paths, selectedAlbumIds);
    final rng = Random();
    final candidates = <AssetEntity>[];

    // Запас кандидатов побольше count: из них потом отбираем count случайных,
    // иначе сет был бы всегда из самых «свежих» ассетов альбома.
    final wanted = count * 6;
    final seenHere = <String>{};

    for (final path in chosen) {
      if (candidates.length >= wanted) break;
      var page = 0;
      const pageSize = 200;
      var scanned = 0;
      final pathCount = await path.assetCountAsync;

      // ВАЖНО: раньше стоял потолок 3000 ассетов на альбом. Если в альбоме
      // 10 000 фото и первые 3 000 уже оценены, приложение считало, что
      // новых фото нет, и оставшиеся 7 000 становились недостижимыми
      // навсегда — пользователь упирался в «пул пуст» при полной галерее.
      // Теперь сканируем альбом целиком; предохранитель нужен только чтобы
      // не зависнуть на огромной библиотеке.
      final maxScan = min(pathCount, _maxScanPerAlbum);

      while (scanned < maxScan && candidates.length < wanted) {
        final assets = await path.getAssetListPaged(page: page, size: pageSize);
        if (assets.isEmpty) break;
        for (final a in assets) {
          scanned++;
          if (excludeIds.contains(a.id)) continue;
          // Альбомы пересекаются: одно фото может лежать и в «Все фото»,
          // и в «Камере». Без этой проверки оно попадало бы в сет дважды.
          if (!seenHere.add(a.id)) continue;
          candidates.add(a);
          if (candidates.length >= wanted) break;
        }
        page++;
      }

      if (scanned >= maxScan &&
          pathCount > maxScan &&
          candidates.length < wanted) {
        debugPrint('[Gallery] ${path.name}: просканировано $maxScan из '
            '$pathCount — часть альбома не просмотрена');
      }
    }

    candidates.shuffle(rng);
    return candidates.take(count).toList(growable: false);
  }

  /// Возвращает id, которые НЕ удалось удалить.
  /// На Android 10+ удаление идёт через системный createDeleteRequest:
  /// после Allow система может удалить файлы асинхронно, а failed-list
  /// бывает ложно непустым — поэтому перепроверяем фактическое наличие.
  Future<List<String>> deleteAssets(List<String> ids) async {
    try {
      final failed = await PhotoManager.editor.deleteWithIds(ids);
      if (failed.isEmpty) return const [];
      final stillThere = <String>[];
      for (final id in failed) {
        final asset = await AssetEntity.fromId(id);
        final exists = asset != null && await asset.exists;
        if (exists) stillThere.add(id);
      }
      return stillThere;
    } catch (e) {
      debugPrint('deleteAssets error: $e');
      return ids;
    }
  }

  Future<AssetPathEntity?> findAlbum(String name) async {
    final paths = await PhotoManager.getAssetPathList(type: RequestType.common);
    for (final p in paths) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// Копирует фото в папку галереи для оценки [rating].
  /// Android: файл копируется в DCIM/Gallerate <rating>.
  /// iOS/macOS: soft-link через copyAssetToPath (если альбом существует).
  Future<bool> copyToRatingFolder({
    required AssetEntity asset,
    required int rating,
  }) async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final album = await findAlbum('Gallerate $rating');
        if (album != null) {
          await PhotoManager.editor.copyAssetToPath(
            asset: asset,
            pathEntity: album,
          );
          return true;
        }
        return false;
      }
      final file = await asset.originFile ?? await asset.file;
      if (file == null) return false;
      await PhotoManager.editor.saveImageWithPath(
        file.path,
        title: asset.title,
        relativePath: 'DCIM/Gallerate $rating',
      );
      return true;
    } catch (e) {
      debugPrint('copyToRatingFolder failed: $e');
      return false;
    }
  }

  List<AssetPathEntity> _choose(
      List<AssetPathEntity> all, List<String>? selectedIds) {
    if (selectedIds == null || selectedIds.isEmpty) return all;
    final byId = {for (final p in all) p.id: p};
    return [
      for (final id in selectedIds)
        if (byId.containsKey(id)) byId[id]!
    ];
  }

  /// Альбомы для сканирования кандидатов.
  ///
  /// При выборе «вся галерея» нельзя идти по всем альбомам подряд: они
  /// пересекаются («Все фото» ⊃ «Камера» ⊃ «Скриншоты»), и мы бы просканировали
  /// библиотеку по нескольку раз. Если среди альбомов есть помеченный isAll,
  /// берём только его — он уже содержит всё.
  List<AssetPathEntity> _chooseForScan(
      List<AssetPathEntity> all, List<String>? selectedIds) {
    if (selectedIds != null && selectedIds.isNotEmpty) {
      return _choose(all, selectedIds);
    }
    final isAll = all.where((p) => p.isAll).toList();
    return isAll.isNotEmpty ? isAll : all;
  }
}
