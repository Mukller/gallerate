import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../core/rating_style.dart';
import '../../data/db.dart';
import '../../data/rating_store.dart';
import '../../logic/app_state.dart';
import '../tab_index.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key, this.store});

  /// Хранилище оценок. По умолчанию — боевая база; в тестах подставляется
  /// фейк (см. комментарий в [BestScreen.store]).
  final RatingStore? store;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  /// null — данные ещё не загружались. Экран живёт в [IndexedStack] и
  /// строится при запуске приложения, когда его вкладка ещё не выбрана;
  /// грузить в [initState] означало бы считать статистику для невидимого
  /// экрана при каждом старте.
  Future<_Bundle>? _future;
  int? _lastSeenTotal;

  RatingStore get _store => widget.store ?? AppDb.instance;

  /// Обновить данные. Будущее вычисляется **до** setState — иначе замыкание
  /// возвращает Future, а Flutter запрещает такое в setState.
  Future<void> _reload() {
    final f = _load();
    // Блок, а не стрелочное замыкание: `() => _future = f` возвращало бы
    // Future, а Flutter такое в setState запрещает.
    setState(() {
      _future = f;
    });
    return f;
  }

  Future<_Bundle> _load() async {
    final db = _store;
    final counts = await db.ratingCounts();
    var likes = 0, dislikes = 0, skips = 0;
    counts.forEach((rating, n) {
      if (rating >= 6) {
        likes += n;
      } else {
        dislikes += n;
      }
    });
    skips = await db.countByRating(0);
    final stats = await db.dayStats();

    final now = DateTime.now();
    final last14 = <_DayValue>[];
    for (var i = 13; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = AppDb.dayKey(d);
      final s = stats[key];
      last14.add(_DayValue(day: d, rated: s?.ratedTotal ?? 0));
    }

    return _Bundle(
      likes: likes,
      dislikes: dislikes,
      skips: skips,
      activeDays: stats.length,
      last14: last14,
      counts: counts,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Статистика должна обновляться сразу после новых оценок,
    // а не только по pull-to-refresh.
    final seen = context.watch<AppState>().seenTotal;
    final visible = context.isTabVisible(TabIndex.stats);
    // Статистика обновляется сама после новых оценок, а не только по
    // pull-to-refresh. Первый показ — единственная причина для загрузки:
    // initState намеренно не трогает базу.
    if (visible && _future == null) {
      _future = _load();
      _lastSeenTotal = seen;
    } else if (visible && _lastSeenTotal != seen) {
      _lastSeenTotal = seen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _reload();
      });
    }
    final future = _future;
    return FutureBuilder<_Bundle>(
      future: future,
      builder: (context, snap) {
        if (!snap.hasData) {
          if (future == null) return const SizedBox.shrink();
          return const Center(child: CircularProgressIndicator());
        }
        final b = snap.data!;
        final total = b.likes + b.dislikes + b.skips;

        return RefreshIndicator(
          onRefresh: () async {
            final f = _load();
            setState(() {
              _future = f;
            });
            await f;
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _BigCard(
                      value: '$total',
                      label: context.tr('statsTotal'),
                      icon: Icons.done_all_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BigCard(
                      value: '${b.activeDays}',
                      label: context.tr('statsActiveDays'),
                      icon: Icons.calendar_month_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('chart14'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 180,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: _maxY(b.last14),
                            barTouchData: BarTouchData(
                              enabled: false,
                            ),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(),
                              leftTitles: const AxisTitles(),
                              rightTitles: const AxisTitles(),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 26,
                                  getTitlesWidget: (v, meta) =>
                                      _dayLabel(v, b.last14),
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            barGroups: [
                              for (var i = 0; i < b.last14.length; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY: b.last14[i].rated.toDouble(),
                                      width: 10,
                                      borderRadius: BorderRadius.circular(5),
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('ratioChart'),
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 160,
                        child: _hasSections(b.counts)
                            ? PieChart(
                                PieChartData(
                                  sectionsSpace: 2,
                                  centerSpaceRadius: 40,
                                  sections: [
                                    for (var r = 1; r <= 10; r++)
                                      if ((b.counts[r] ?? 0) > 0)
                                        PieChartSectionData(
                                          value: b.counts[r]!.toDouble(),
                                          color: _ratingColor(r),
                                          radius: 42,
                                          title: '$r',
                                          titleStyle: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                  ],
                                ),
                              )
                            : Center(
                                child: Text(
                                  context.tr('statsEmpty'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _Legend(
                            color: Colors.green.shade600,
                            label: context.tr('statsLikePct'),
                            value: b.likes,
                          ),
                          const SizedBox(width: 24),
                          _Legend(
                            color: Colors.red.shade500,
                            label: context.tr('statsDislikePct'),
                            value: b.dislikes,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  /// Есть ли что рисовать: у пользователя могут быть только пропуски (rating 0),
  /// которые в ratingCounts() не попадают — PieChart с пустым sections нельзя.
  static bool _hasSections(Map<int, int> counts) {
    for (var r = 1; r <= 10; r++) {
      if ((counts[r] ?? 0) > 0) return true;
    }
    return false;
  }

  double _maxY(List<_DayValue> values) {
    var m = 0;
    for (final v in values) {
      if (v.rated > m) m = v.rated;
    }
    return (m <= 0 ? 5 : m + 1).toDouble();
  }

  Color _ratingColor(int r) => RatingStyle.color(r);

  Widget _dayLabel(double v, List<_DayValue> values) {
    final i = v.toInt();
    if (i < 0 || i >= values.length) return const SizedBox.shrink();
    final d = values[i].day;
    final label = d.day.toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(label, style: const TextStyle(fontSize: 9)),
    );
  }
}

class _Bundle {
  _Bundle({
    required this.likes,
    required this.dislikes,
    required this.skips,
    required this.activeDays,
    required this.last14,
    required this.counts,
  });

  final int likes;
  final int dislikes;
  final int skips;
  final int activeDays;
  final List<_DayValue> last14;
  final Map<int, int> counts;
}

class _DayValue {
  _DayValue({required this.day, required this.rated});

  final DateTime day;
  final int rated;
}

class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label · $value', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
