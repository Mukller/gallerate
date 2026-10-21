import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../core/rating_style.dart';
import '../../data/models.dart';
import '../../logic/app_state.dart';
import '../settings/settings_screen.dart';
import '../summary/summary_screen.dart';
import 'card_deck.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final GlobalKey<SwipeCardDeckState> _deckKey =
      GlobalKey<SwipeCardDeckState>();

  int? _summaryPushedForSetId;

  // Ассеты кэшируем заранее: иначе на каждый сдвиг курсора создавался бы
  // новый Future, FutureBuilder уходил в loading и колода пропадала
  // в спиннер после каждого свайпа.
  final Map<String, AssetEntity> _assetCache = {};
  int _loadedSetId = -1;
  bool _prefetching = false;
  bool _loadingWindow = false;
  String? _prunedKey;

  static const int _windowSize = 3;
  static const int _prefetchLimit = 12;

  /// Окно visible-карточек, собранное СИНХРОННО из кэша.
  List<AssetEntity> _windowFor(SetInfo set) {
    final out = <AssetEntity>[];
    for (final id in set.assetIds.skip(set.cursor).take(_windowSize)) {
      final a = _assetCache[id];
      if (a != null) out.add(a);
    }
    return out;
  }

  bool _needsFetch(SetInfo set) {
    for (final id in set.assetIds.skip(set.cursor).take(_windowSize)) {
      if (!_assetCache.containsKey(id)) return true;
    }
    return false;
  }

  /// Догружает окно + упреждающе кэширует остаток сета.
  ///
  /// Два флага, а не один: загрузка окна и упреждающая догрузка идут
  /// параллельно, и общий флаг делал вторую бессмысленной. Раньше
  /// `_prefetchAhead` вызывался изнутри `_ensureLoaded` при уже поднятом
  /// `_prefetching`, а сам `_prefetchAhead` выходил по этому же флагу —
  /// то есть упреждающая загрузка не запускалась НИКОГДА. Кэш содержал
  /// только текущее окно из трёх фото, и после третьего свайпа карточка
  /// пропадала и появлялась снова со спиннером.
  Future<void> _ensureLoaded(SetInfo set) async {
    if (_loadingWindow) return;
    if (_loadedSetId != set.id) {
      _loadedSetId = set.id;
      _assetCache.clear();
    }
    if (_needsFetch(set)) {
      _loadingWindow = true;
      try {
        for (final id in set.assetIds.skip(set.cursor).take(_windowSize)) {
          if (_assetCache.containsKey(id)) continue;
          final a = await AssetEntity.fromId(id);
          if (a != null) _assetCache[id] = a;
        }
        if (mounted) setState(() {});
      } finally {
        _loadingWindow = false;
      }
    }
    // Упреждающе кэшируем остаток сета — отдельным флагом, иначе вызов
    // изнутри загрузки окна всегда выходил бы сразу.
    unawaited(_prefetchAhead(set));
  }

  Future<void> _prefetchAhead(SetInfo set) async {
    if (_prefetching) return;
    _prefetching = true;
    var added = 0;
    try {
      for (final id in set.assetIds.skip(set.cursor).take(_prefetchLimit)) {
        if (_assetCache.containsKey(id)) continue;
        final a = await AssetEntity.fromId(id);
        if (a != null) {
          _assetCache[id] = a;
          added++;
        }
        if (!mounted) return;
      }
      // Перестраиваемся только если реально что-то добавили,
      // иначе получим бесконечный цикл rebuild -> postFrame -> prefetch.
      if (added > 0 && mounted) setState(() {});
    } finally {
      _prefetching = false;
    }
  }

  void _scheduleLoad(SetInfo set) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_needsFetch(set)) _ensureLoaded(set);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // Ошибка записи оценки: карточка уже улетела, а оценка не сохранилась.
    // Молчать об этом нельзя — пользователь решит, что свайп не засчитался.
    final err = app.lastError;
    if (err != null) {
      app.lastError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err)),
        );
      });
    }

    if (!app.hasAccess) {
      return _CenteredMessage(
        icon: Icons.lock_outline,
        title: context.tr('permTitle'),
        actionLabel: context.tr('permButton'),
        onAction: app.grantPermission,
      );
    }

    final set = app.activeSet;

    if (app.generating && set == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (app.poolEmpty && (set == null || !set.hasPending)) {
      return _CenteredMessage(
        icon: Icons.inventory_2_outlined,
        title: context.tr('emptyPoolTitle'),
        subtitle: context.tr('emptyPoolBody'),
        extra: context.tr('emptyPoolExtra'),
        actionLabel: context.tr('albumsLabel'),
        onAction: () => _openSettings(context),
      );
    }

    if (set == null) {
      return _WaitingView(
        timeText: app.appearTimeString,
        onOpenEarly: () => app.startExtraSet(),
      );
    }

    if (!set.hasPending) {
      // Сводка уже показывалась — показываем понятное состояние, а НЕ
      // вечный спиннер. Раньше здесь крутился CircularProgressIndicator
      // навсегда: сводка второй раз не открывалась (флаг по id сета), а
      // set == null (ожидание) не выполнялось, потому что закрытый набор
      // оставался в app.activeSet. Пользователь оставался с экрана без
      // единой кнопки.
      if (_summaryPushedForSetId == set.id) {
        return _SetDoneView(
          timeText: app.appearTimeString,
          onMore: () => app.startExtraSet(),
        );
      }
      _maybePushSummary(app);
      return const Center(child: CircularProgressIndicator());
    }

    _resetSummaryFlag(set.id);
    // Пропускаем ассеты, исчезнувшие с устройства, чтобы assets[0] окна
    // всегда совпадал с set.currentId.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Проверяем один раз на каждый сдвиг курсора: pruneMissingAssets делает
      // IPC-вызов AssetEntity.fromId, а build вызывается очень часто.
      final key = '${set.id}:${set.cursor}';
      if (key == _prunedKey) return;
      _prunedKey = key;
      app.pruneMissingAssets();
    });
    _scheduleLoad(set);

    final window = _windowFor(set);
    final total = set.assetIds.length;
    final done = set.cursor.clamp(0, total);

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : done / total,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$done / $total',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (app.currentStreak > 0) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade700,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_fire_department,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '${app.currentStreak}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                // Отмена последней оценки. Кнопка появляется только когда
                // отменять есть что: обещать действие, которого нельзя
                // выполнить, хуже, чем не показать кнопку вовсе.
                if (app.canUndo) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    // Пока карточка летит, оценка ещё не записана, а
                    // отмена пересобирает набор и сбрасывает колоду —
                    // неотправленная оценка пропала бы молча. Поэтому в
                    // этот момент отмена запрещена.
                    onPressed: () {
                      if (_deckKey.currentState?.isBusy ?? false) return;
                      app.undoLastRating();
                    },
                    icon: const Icon(Icons.undo_rounded, size: 20),
                    color: Theme.of(context).colorScheme.outline,
                    tooltip: context.tr('undo'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: window.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : SwipeCardDeck(
                      key: _deckKey,
                      assets: window,
                      onRated: (rating) => app.rateCurrent(
                        rating,
                        // Дата съёмки нужна, чтобы потом сортировать
                        // «Лучшие» и очередь уборки по возрасту снимка.
                        takenAt: _takenAtOf(set),
                      ),
                      onSkip: () => app.skipCurrent(),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final r in const [1, 3, 5])
                  _RateChip(
                    rating: r,
                    onTap: () => _deckKey.currentState?.programmaticRate(r),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _deckKey.currentState?.programmaticSkip(),
                  icon: const Icon(Icons.redo_outlined, size: 18),
                  label: Text(context.tr('skip')),
                ),
                for (final r in const [6, 8, 10])
                  _RateChip(
                    rating: r,
                    onTap: () => _deckKey.currentState?.programmaticRate(r),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              context.tr('swipeHint'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// Когда сделан текущий снимок (мс с эпохи), если ассет уже загружен.
  int? _takenAtOf(SetInfo set) {
    final id = set.currentId;
    if (id == null) return null;
    final asset = _assetCache[id];
    if (asset == null) return null;
    return asset.createDateTime.millisecondsSinceEpoch;
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _maybePushSummary(AppState app) {
    final set = app.activeSet;
    if (set == null) return;
    if (_summaryPushedForSetId == set.id) return;
    _summaryPushedForSetId = set.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        // Хранилище передаём явно: иначе сводка пошла бы в глобальную
        // базу, и экран нельзя было бы проверить тестом.
        builder: (_) => SummaryScreen(set: set, store: app.store),
      ));
      if (mounted) setState(() {});
    });
  }

  void _resetSummaryFlag(int setId) {
    if (_summaryPushedForSetId != null && _summaryPushedForSetId != setId) {
      _summaryPushedForSetId = null;
    }
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.extra,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? extra;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (extra != null) ...[
              const SizedBox(height: 4),
              Text(
                extra!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  const _WaitingView({
    required this.timeText,
    required this.onOpenEarly,
  });

  final String timeText;
  final VoidCallback onOpenEarly;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded,
                size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(context.tr('waitingTitle'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              context.tr('waitingBody', {'time': timeText}),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            TextButton(
              onPressed: onOpenEarly,
              child: Text(context.tr('openEarly')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Набор пройден, сводка уже показана.
class _SetDoneView extends StatelessWidget {
  const _SetDoneView({required this.timeText, required this.onMore});

  final String timeText;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt_rounded,
                size: 72, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(context.tr('setDoneTitle'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              context.tr('setDoneBody', {'time': timeText}),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onMore,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(context.tr('oneMore')),
            ),
          ],
        ),
      ),
    );
  }
}

class _RateChip extends StatelessWidget {
  const _RateChip({required this.rating, required this.onTap});

  final int rating;
  final VoidCallback onTap;

  static const _emoji = RatingStyle.emoji;

  static Color _colorFor(int r) => RatingStyle.color(r);

  @override
  Widget build(BuildContext context) {
    final emoji = _emoji[rating];
    final color = _colorFor(rating);
    return Semantics(
      button: true,
      label: 'Rate $rating out of 10',
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: emoji != null
                ? ExcludeSemantics(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  )
                : SizedBox(
                    width: 26,
                    height: 26,
                    child: Center(
                      child: Text(
                        '$rating',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
