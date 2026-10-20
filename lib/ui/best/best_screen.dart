import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../core/rating_style.dart';
import '../../data/db.dart';
import '../../data/rating_store.dart';
import '../../data/gallery_service.dart';
import '../../data/models.dart';
import '../../logic/app_state.dart';
import '../tab_index.dart';
import 'asset_image.dart';
import 'rating_chip.dart';

class BestScreen extends StatefulWidget {
  const BestScreen({super.key, this.store});

  /// Хранилище оценок. По умолчанию — боевая база; в тестах подставляется
  /// фейк: читать SQLite прямо из виджета нельзя, операции БД внутри
  /// виджет-тестов не завершаются и тест зависает.
  final RatingStore? store;

  @override
  State<BestScreen> createState() => _BestScreenState();
}

class _BestScreenState extends State<BestScreen> {
  /// Боевая база или подставленный в тестах фейк.
  RatingStore get _store => widget.store ?? AppDb.instance;
  Map<int, int> _counts = {};
  int _selected = 10;
  late Future<List<PhotoRow>> _gridFuture;
  int _lastSeenTotal = -1;
  bool _sorting = false;
  int _sortProgress = 0;
  int _sortTotal = 0;
  late final StreamController<int> _unsortedCtrl;
  late final Stream<int> _unsortedStream;

  @override
  void initState() {
    super.initState();
    _unsortedCtrl = StreamController<int>.broadcast();
    _unsortedStream = _unsortedCtrl.stream;
    _refreshUnsorted();
    _reload();
  }

  @override
  void dispose() {
    _unsortedCtrl.close();
    super.dispose();
  }

  void _refreshUnsorted() async {
    final n = await _store.unsortedCount();
    if (mounted) _unsortedCtrl.add(n);
  }

  Future<void> _reshuffle() async {
    final sorted = await _store.sortedCount();
    if (!mounted) return;
    if (sorted == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('sortNone'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('reshuffleTitle')),
        content: Text(ctx.tr('reshuffleBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('reshuffle')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final n = await _store.markAllUnsorted();
    _refreshUnsorted();
    _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('reshuffled', {'n': '$n'})),
        ),
      );
    }
  }

  void _reload() {
    _store.ratingCounts().then((c) {
      if (mounted) setState(() => _counts = c);
    });
    setState(() {
      _gridFuture = _store.rowsByRating(_selected);
    });
    _refreshUnsorted();
  }

  void _select(int rating) {
    setState(() {
      _selected = rating;
      _gridFuture = _store.rowsByRating(rating);
    });
  }

  Future<void> _sortToGallery() async {
    final unsorted = await _store.unsortedRatedRows();
    if (!mounted) return;
    if (unsorted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('sortNone'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('sortConfirmTitle')),
        content: Text(ctx.tr('sortConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('sortToGallery')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sorting = true;
      _sortProgress = 0;
      _sortTotal = unsorted.length;
    });

    var sortedIds = <String>[];
    try {
      final done = <String>[];
      for (final row in unsorted) {
        final asset = await AssetEntity.fromId(row.id);
        if (asset == null) continue;
        final ok = await GalleryService.instance.copyToRatingFolder(
          asset: asset,
          rating: row.rating,
        );
        if (ok) done.add(row.id);
        if (mounted) {
          setState(() => _sortProgress = done.length);
        }
      }
      sortedIds = done;
      await _store.markSorted(sortedIds);
    } finally {
      if (mounted) {
        setState(() => _sorting = false);
        _reload();
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr('sortedDone', {'n': '${sortedIds.length}'}),
        ),
      ),
    );
  }

  static const _emoji = RatingStyle.emoji;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Перечитываем только когда вкладка видима: IndexedStack держит все
    // экраны живыми, иначе каждая оценка дёргала бы БД на «Лучших».
    if (app.seenTotal != _lastSeenTotal &&
        context.isTabVisible(TabIndex.best)) {
      _lastSeenTotal = app.seenTotal;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                // Раньше здесь был горизонтальный ListView с reverse: true.
                // Из-за reverse выбранный по умолчанию рейтинг 10 оказывался
                // за границей viewport и рисовался обрезанным: прямые углы,
                // без эмодзи и без числа. Wrap исключает обрезку в принципе.
                Expanded(
                  child: RatingChipRow(
                    selected: _selected,
                    counts: _counts,
                    onSelect: _select,
                  ),
                ),
                const SizedBox(width: 8),
                const _UnsortedAndActions(),
              ],
            ),
          ),
          if (_sorting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LinearProgressIndicator(
                value: _sortTotal == 0 ? null : _sortProgress / _sortTotal,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<PhotoRow>>(
              future: _gridFuture,
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
                          Text(_emoji[_selected] ?? '$_selected',
                              style: const TextStyle(fontSize: 56)),
                          const SizedBox(height: 12),
                          Text(context.tr('bestEmptyTitle'),
                              style: Theme.of(context).textTheme.titleLarge),
                        ],
                      ),
                    ),
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return GestureDetector(
                      onTap: () => _openViewer(context, row.id),
                      onLongPress: () => _rerate(context, row.id, row.rating),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AssetEntityImageLoader(assetId: row.id),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: RatingStyle.badge(
                                row.rating,
                                color:
                                    row.sorted ? Colors.green.shade600 : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openViewer(BuildContext context, String assetId) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullscreenViewer(assetId: assetId),
    ));
  }

  /// Долгое нажатие по фото — переоценка (ошибочный свайп можно исправить).
  Future<void> _rerate(
      BuildContext context, String assetId, int current) async {
    final app = context.read<AppState>();
    final picked = await RatingEditSheet.show(context, current);
    if (picked == null || !mounted) return;
    await app.rerate(assetId, picked);
    _reload();
  }
}

/// Бейдж «N новых» и кнопки «пересортировать» / «разложить в галерее».
class _UnsortedAndActions extends StatelessWidget {
  const _UnsortedAndActions();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_BestScreenState>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StreamBuilder<int>(
          stream: state._unsortedStream,
          builder: (context, snap) {
            final n = snap.data ?? 0;
            if (n == 0) return const SizedBox.shrink();
            return Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                context.tr('unsortedBadge', {'n': '$n'}),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade900,
                ),
              ),
            );
          },
        ),
        IconButton(
          tooltip: context.tr('reshuffle'),
          onPressed: state._reshuffle,
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          tooltip: context.tr('sortToGallery'),
          onPressed: state._sorting ? null : state._sortToGallery,
          icon: state._sorting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_album_outlined),
        ),
      ],
    );
  }
}

class _FullscreenViewer extends StatelessWidget {
  const _FullscreenViewer({required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: AssetEntityImageLoader(assetId: assetId),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                color: Colors.white,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
