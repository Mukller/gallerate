import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../ui/list_error_view.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../data/rating_store.dart';
import '../../logic/app_state.dart';
import '../best/asset_image.dart';
import '../tab_index.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.store});

  /// Хранилище оценок. По умолчанию — боевая база; в тестах подставляется
  /// фейк (см. комментарий в [BestScreen.store]).
  final RatingStore? store;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// null — данные ещё не загружались. Экран живёт в [IndexedStack] и
  /// строится при запуске приложения, когда его вкладка ещё не выбрана,
  /// поэтому грузить в [initState] нельзя: сводка по всем дням — тяжёлый
  /// запрос, и он выполнялся бы для невидимого экрана.
  Future<List<_DayBlock>>? _future;
  String? _lastSeenTotal;

  RatingStore get _store => widget.store ?? AppDb.instance;

  /// Обновить данные. Будущее вычисляется **до** setState: если передать в
  /// setState замыкание вида `() => _future = _load()`, оно возвращает Future,
  /// а Flutter это прямо запрещает («setState() callback argument returned a
  /// Future») — падение в debug на каждом обновлении сводки.
  Future<void> _reload() {
    final f = _load();
    // Именно блок, а не `() => _future = f`: присваивание в Dart само по себе
    // даёт значение, поэтому стрелочное замыкание вернуло бы Future и Flutter
    // выбросил бы «setState() callback argument returned a Future».
    setState(() {
      _future = f;
    });
    return f;
  }

  Future<List<_DayBlock>> _load() async {
    final stats = await _store.dayStats();
    final days = stats.keys.toList()..sort((a, b) => b.compareTo(a));
    final limited = days.take(30).toList(growable: false);
    final rowsByDay = await _store.recentRowsPerDay(limited);
    return [
      for (final day in limited)
        _DayBlock(
          stat: stats[day]!,
          rows: rowsByDay[day] ?? const [],
        )
    ];
  }

  String _pretty(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    return '${p[2]}.${p[1]}.${p[0]}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // Сигнал обновления — пара «сколько оценено + ревизия данных»:
    // переоценка не меняет количество оцененных фото, но меняет их
    // распределение по дням и по оценкам.
    final seen = '${app.seenTotal}:${app.dataRevision}';
    final visible = context.isTabVisible(TabIndex.history);
    // Первый показ — единственная причина, по которой экран что-то грузит:
    // initState намеренно не трогает базу.
    if (visible && _future == null) {
      _future = _load();
      // Снимок счётчика, чтобы следующий показ перезагрузил данные только
      // если оценки действительно изменились.
      _lastSeenTotal = seen;
    } else if (visible && _lastSeenTotal != seen) {
      _lastSeenTotal = seen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    final future = _future;
    return FutureBuilder<List<_DayBlock>>(
      future: future,
      builder: (context, snap) {
        if (snap.hasError) {
          return ListErrorView(
            onRetry: _reload,
            detail: '${snap.error}',
          );
        }
        if (!snap.hasData) {
          if (future == null) return const SizedBox.shrink();
          return const Center(child: CircularProgressIndicator());
        }
        final blocks = snap.data!;
        if (blocks.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_edu,
                      size: 72, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    context.tr('historyEmpty'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            final f = _load();
            setState(() {
              _future = f;
            });
            await f;
          },
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: blocks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = blocks[i];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _pretty(b.stat.day),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          _Chip(
                              color: Colors.green.shade600,
                              icon: Icons.favorite_rounded,
                              n: b.stat.likes),
                          const SizedBox(width: 6),
                          _Chip(
                              color: Colors.red.shade500,
                              icon: Icons.close_rounded,
                              n: b.stat.dislikes),
                          if (b.stat.skips > 0) ...[
                            const SizedBox(width: 6),
                            _Chip(
                              color: Theme.of(context).colorScheme.outline,
                              icon: Icons.redo_outlined,
                              n: b.stat.skips,
                            ),
                          ],
                        ],
                      ),
                      if (b.rows.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 88,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: b.rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 6),
                            itemBuilder: (context, j) {
                              final row = b.rows[j];
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 88,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      AssetEntityImageLoader(assetId: row.id),
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.black54,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${row.rating}',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _DayBlock {
  _DayBlock({required this.stat, required this.rows});

  final DayStat stat;
  final List<PhotoRow> rows;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.color, required this.icon, required this.n});

  final Color color;
  final IconData icon;
  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$n',
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
