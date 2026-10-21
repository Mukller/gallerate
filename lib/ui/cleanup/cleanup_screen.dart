import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../core/rating_style.dart';
import '../../data/db.dart';
import '../../data/rating_store.dart';
import '../../data/gallery_service.dart';
import '../../data/gallery_source.dart';
import '../../data/models.dart';
import '../../logic/app_state.dart';
import '../best/asset_image.dart';
import '../tab_index.dart';

class CleanupScreen extends StatefulWidget {
  const CleanupScreen({super.key, this.store, this.gallery});

  /// Хранилище оценок. По умолчанию — боевая база; в тестах подставляется
  /// фейк (см. комментарий в [BestScreen.store]).
  final RatingStore? store;

  /// Галерея. Нужна для удаления файлов с устройства — операции, которую
  /// необратимо, поэтому она тоже должна быть подменяемой в тестах.
  final GallerySource? gallery;

  @override
  State<CleanupScreen> createState() => _CleanupScreenState();
}

class _CleanupScreenState extends State<CleanupScreen> {
  RatingStore get _store => widget.store ?? AppDb.instance;

  GallerySource get _gallery => widget.gallery ?? GalleryService.instance;

  late Future<List<PhotoRow>> _future;
  final Set<String> _selected = {};
  bool _deleting = false;
  List<PhotoRow> _rows = const [];
  int _lastSeenTotal = -1;

  @override
  void initState() {
    super.initState();
    _future = _loadRows();
  }

  /// Читаем список и сразу обновляем _rows, чтобы нижняя панель
  /// («Выбрать все») считала по актуальным данным.
  Future<List<PhotoRow>> _loadRows() async {
    final rows = await _store.lowRatedRows();
    if (mounted) setState(() => _rows = rows);
    return rows;
  }

  void _reload() {
    setState(() {
      _selected.clear();
      _future = _loadRows();
    });
  }

  Future<void> _rerate(String assetId, int current) async {
    final picked = await RatingEditSheet.show(context, current);
    if (picked == null || !mounted) return;
    await context.read<AppState>().rerate(assetId, picked);
    _reload();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selected.length == _rows.length && _rows.isNotEmpty) {
        _selected.clear();
      } else {
        _selected.addAll(_rows.map((r) => r.id));
      }
    });
  }

  Future<void> _deleteSelected(AppState app) async {
    if (_selected.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('confirmDeleteTitle')),
        content: Text(ctx.tr('confirmDeleteBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('deleteWord')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final ids = _selected.toList(growable: false);
    final failed = await _gallery.deleteAssets(ids);
    final deletedIds = ids.where((id) => !failed.contains(id)).toList();
    await _store.markDeleted(deletedIds);
    await app.refreshCollections();

    if (!mounted) return;
    setState(() => _deleting = false);
    if (deletedIds.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('deletedToast', {'n': '${deletedIds.length}'}),
          ),
        ),
      );
    }
    if (failed.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('failedToast', {'n': '${failed.length}'}),
          ),
        ),
      );
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Новые оценки меняют очередь — перечитываем.
    if (app.seenTotal != _lastSeenTotal &&
        context.isTabVisible(TabIndex.cleanup)) {
      _lastSeenTotal = app.seenTotal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    return Scaffold(
      body: FutureBuilder<List<PhotoRow>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cleaning_services_outlined,
                        size: 72, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(context.tr('cleanupEmptyTitle'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      context.tr('cleanupEmptyBody'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final row = rows[i];
              final isSelected = _selected.contains(row.id);
              return GestureDetector(
                onTap: () => setState(() {
                  isSelected ? _selected.remove(row.id) : _selected.add(row.id);
                }),
                // Долгое нажатие — переоценка. Особенно важно здесь:
                // фото с оценкой 1-5 идёт на удаление, и ошибиться
                // в оценке = потерять хорошее фото.
                onLongPress: () => _rerate(row.id, row.rating),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AssetEntityImageLoader(
                        // Ключ с идентификатором: по нему виджет-тест
                        // выбирает нужное фото, а не «первое попавшееся».
                        key: ValueKey('cleanup_photo_${row.id}'),
                        assetId: row.id,
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: RatingStyle.badge(row.rating),
                    ),
                    if (isSelected)
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.black38,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.error,
                            width: 3,
                          ),
                        ),
                      ),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Icon(
                        isSelected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: isSelected
                            ? Theme.of(context).colorScheme.error
                            : Colors.white70,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _toggleSelectAll,
                        icon: Icon(
                            _selected.length == _rows.length && _rows.isNotEmpty
                                ? Icons.deselect
                                : Icons.select_all),
                        label: Text(
                          _selected.length == _rows.length && _rows.isNotEmpty
                              ? context.tr('deselectAll')
                              : context.tr('selectAll'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed:
                            _deleting ? null : () => _deleteSelected(app),
                        icon: _deleting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.delete_forever_rounded),
                        label: Text(
                          '${context.tr('deleteSelected')} · '
                          '${context.tr('selectedCount', {
                                'n': '${_selected.length}'
                              })}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
