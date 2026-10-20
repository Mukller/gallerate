import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../data/db.dart';
import '../../data/models.dart';
import '../../data/rating_store.dart';
import '../../logic/app_state.dart';

class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key, required this.set, this.store});

  final SetInfo set;

  /// Хранилище оценок. По умолчанию — боевая база; в тестах подставляется
  /// фейк (см. комментарий в [BestScreen.store]).
  final RatingStore? store;

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  late Future<_SummaryData> _future;

  RatingStore get _store => widget.store ?? AppDb.instance;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SummaryData> _load() async {
    final db = _store;
    final ids = widget.set.assetIds;
    // Один запрос вместо N: set.assetIds может содержать до 50 элементов.
    final rows = await db.ratingsForAssets(ids);
    var liked = 0, disliked = 0, skips = 0, sum = 0, n = 0;
    for (final r in rows.values) {
      if (r == 0) {
        skips++;
      } else {
        sum += r;
        n++;
        if (r >= 6) {
          liked++;
        } else {
          disliked++;
        }
      }
    }
    final totalAll = await db.totalSeen();
    return _SummaryData(
      liked: liked,
      disliked: disliked,
      skips: skips,
      totalAll: totalAll,
      avg: n == 0 ? null : sum / n,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(context.tr('summaryTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<_SummaryData>(
          future: _future,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data!;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _StatCard(
                        color: Colors.purple.shade600,
                        icon: Icons.star_rounded,
                        value: d.avg == null ? '—' : d.avg!.toStringAsFixed(1),
                        label: context.tr('avg'),
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        color: Colors.green.shade600,
                        icon: Icons.favorite_rounded,
                        value: '${d.liked}',
                        label: context.tr('sumLiked'),
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        color: Colors.red.shade500,
                        icon: Icons.delete_outline_rounded,
                        value: '${d.disliked}',
                        label: context.tr('sumDisliked'),
                      ),
                      const SizedBox(width: 12),
                      _StatCard(
                        color: Theme.of(context).colorScheme.outline,
                        icon: Icons.redo_outlined,
                        value: '${d.skips}',
                        label: context.tr('sumSkipped'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _Row(
                            label: context.tr('sumTotalAll'),
                            value: '${d.totalAll}',
                          ),
                          const Divider(height: 24),
                          _Row(
                            label: context.tr(
                                'sumGallery', {'pct': '${app.curatedPercent}'}),
                            value: '${app.seenTotal}/${app.galleryTotal}',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () async {
                      await app.startExtraSet();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(context.tr('oneMore')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text(context.tr('toCleanup')),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryData {
  _SummaryData({
    required this.liked,
    required this.disliked,
    required this.skips,
    required this.totalAll,
    required this.avg,
  });

  final int liked;
  final int disliked;
  final int skips;
  final int totalAll;
  final double? avg;
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.color,
    required this.icon,
    required this.value,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Text(label)),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}
