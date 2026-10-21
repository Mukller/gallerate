import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Полноэкранный просмотр фото.
///
/// В колоде фото показано превью 1200 px по меньшей стороне, и разглядеть
/// снимок (размытость, артефакты, лишний палец в углу) невозможно — а
/// именно по этому и решается, оставлять фото или удалять. Тап по карточке
/// открывает фото целиком, с щипковым масштабированием.
class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  /// Трансформация: масштаб и смещение.
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Прозрачный маршрут: колода остаётся видна под фото, и закрыть
      // просмотр можно тапом, а не кнопкой.
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Просмотр изображения: щипок — масштаб, двойной тап — сброс.
            InteractiveViewer(
              transformationController: _controller,
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: _FullImage(asset: widget.asset),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Изображение в исходном качестве (насколько позволяет галерея).
class _FullImage extends StatefulWidget {
  const _FullImage({required this.asset});

  final AssetEntity asset;

  @override
  State<_FullImage> createState() => _FullImageState();
}

class _FullImageState extends State<_FullImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    // Размер побольше, чем у превью в колоде: 2048 px — это уже видно
    // на телефоне, а оригинал тянуть опасно: на старых снимках это
    // десятки мегабайт на файл.
    _future = widget.asset
        .thumbnailDataWithSize(const ThumbnailSize(2048, 2048))
        .then<Uint8List?>((v) => v)
        .catchError((_) => null);
  }

  @override
  void didUpdateWidget(covariant _FullImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          // Пока грузится (или если не загрузилось) — нейтральный фон.
          return const ColoredBox(color: Colors.black);
        }
        return Image.memory(bytes, fit: BoxFit.contain);
      },
    );
  }
}

/// Открывает просмотр фото поверх текущего экрана.
void openPhotoViewer(BuildContext context, AssetEntity asset) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => PhotoViewerPage(asset: asset),
    ),
  );
}
