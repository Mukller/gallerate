import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/l10n.dart';
import '../../data/gallery_service.dart';
import '../../data/gallery_source.dart';

class AlbumPickerScreen extends StatefulWidget {
  const AlbumPickerScreen({
    super.key,
    required this.initiallySelected,
    this.gallery,
  });

  final List<String> initiallySelected;

  /// Галерея. По умолчанию — боевая; в тестах подставляется фейк.
  final GallerySource? gallery;

  @override
  State<AlbumPickerScreen> createState() => _AlbumPickerScreenState();
}

class _AlbumPickerScreenState extends State<AlbumPickerScreen> {
  late Future<List<AssetPathEntity>> _future;
  late Set<String> _selected;
  bool _useAll = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initiallySelected.toSet();
    _useAll = _selected.isEmpty;
    _future = (widget.gallery ?? GalleryService.instance).albums();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('chooseAlbums')),
        actions: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).okButtonLabel,
            icon: const Icon(Icons.check_rounded),
            onPressed: () => Navigator.of(context)
                .pop(_useAll ? <String>[] : _selected.toList()),
          ),
        ],
      ),
      body: FutureBuilder<List<AssetPathEntity>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            if (snap.hasError) {
              return _Empty(context.tr('albumsError'));
            }
            return const Center(child: CircularProgressIndicator());
          }
          final albums = snap.data ?? const <AssetPathEntity>[];
          if (albums.isEmpty) {
            return _Empty(context.tr('albumsError'));
          }
          return Column(
            children: [
              SwitchListTile(
                title: Text(context.tr('useAll')),
                value: _useAll,
                onChanged: (v) => setState(() {
                  _useAll = v;
                  if (v) _selected.clear();
                }),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: albums.length,
                  itemBuilder: (context, i) {
                    final album = albums[i];
                    return FutureBuilder<int>(
                      future: album.assetCountAsync,
                      builder: (context, snap) {
                        final count = snap.data ?? 0;
                        final checked = _selected.contains(album.id);
                        return CheckboxListTile(
                          value: _useAll ? true : checked,
                          title: Text(album.name),
                          subtitle: Text(
                            context.tr('photosCount', {'n': '$count'}),
                          ),
                          onChanged: _useAll
                              ? null
                              : (v) => setState(() {
                                    v == true
                                        ? _selected.add(album.id)
                                        : _selected.remove(album.id);
                                  }),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
