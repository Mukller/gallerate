import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/rating_style.dart';
import 'photo_viewer.dart';

enum _DeckPhase { idle, dragging, flying, returning, skipping }

class SwipeCardDeck extends StatefulWidget {
  const SwipeCardDeck({
    super.key,
    required this.assets,
    required this.onRated,
    required this.onSkip,
    this.debugGestures = false,
  });

  final List<AssetEntity> assets;
  final ValueChanged<int> onRated;
  final VoidCallback onSkip;
  final bool debugGestures;

  @override
  SwipeCardDeckState createState() => SwipeCardDeckState();
}

class SwipeCardDeckState extends State<SwipeCardDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  _DeckPhase _phase = _DeckPhase.idle;
  int? _pendingRating;
  Offset _drag = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  Curve _curve = Curves.linear;

  static const double _maxAngle = 0.28;

  double get _w => MediaQuery.of(context).size.width;
  double get _h => MediaQuery.of(context).size.height;

  double get _commitStart => _w * 0.16;
  double get _maxDrag => _w * 0.92;

  bool get _busy => _phase != _DeckPhase.idle && _phase != _DeckPhase.dragging;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTick);
    _ctrl.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(covariant SwipeCardDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldFirst =
        oldWidget.assets.isEmpty ? null : oldWidget.assets.first.id;
    final newFirst = widget.assets.isEmpty ? null : widget.assets.first.id;
    if (oldFirst != newFirst) {
      setState(() {
        _phase = _DeckPhase.idle;
        _drag = Offset.zero;
        _pendingRating = null;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTick() {
    final t = _curve.transform(_ctrl.value);
    setState(() => _drag = Offset.lerp(_from, _to, t)!);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    switch (_phase) {
      case _DeckPhase.flying:
        final rating = _pendingRating;
        _finishInteraction();
        if (rating != null) widget.onRated(rating);
        break;
      case _DeckPhase.skipping:
        _finishInteraction();
        widget.onSkip();
        break;
      case _DeckPhase.returning:
      case _DeckPhase.idle:
      case _DeckPhase.dragging:
        _finishInteraction();
        break;
    }
  }

  void _finishInteraction() {
    setState(() {
      _phase = _DeckPhase.idle;
      _drag = Offset.zero;
      _pendingRating = null;
    });
  }

  void _animateTo(Offset target, Curve curve, _DeckPhase phase) {
    _from = _drag;
    _to = target;
    _curve = curve;
    _phase = phase;
    _ctrl.forward(from: 0);
  }

  void _onPanStart(DragStartDetails _) {
    if (_busy || widget.assets.isEmpty) return;
    _ctrl.stop();
    setState(() => _phase = _DeckPhase.dragging);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_phase != _DeckPhase.dragging) return;
    setState(() => _drag += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    if (_phase != _DeckPhase.dragging) return;
    final v = d.velocity.pixelsPerSecond;
    final vel = math.sqrt(v.dx * v.dx + v.dy * v.dy);
    final dist = _drag.distance;

    final rating = ratingForOffset(_drag, vel);
    if (rating == 0) {
      HapticFeedback.lightImpact();
      _animateTo(Offset.zero, Curves.elasticOut, _DeckPhase.returning);
      return;
    }
    if (dist >= _commitStart || vel > 700) {
      HapticFeedback.mediumImpact();
      _fly(rating);
    } else {
      HapticFeedback.selectionClick();
      _animateTo(Offset.zero, Curves.elasticOut, _DeckPhase.returning);
    }
  }

  void _onPanCancel() {
    if (_phase == _DeckPhase.dragging) {
      _animateTo(Offset.zero, Curves.easeOutBack, _DeckPhase.returning);
    }
  }

  /// Оценка 1..10 ТОЛЬКО по горизонтальному свайпу.
  /// Вправо → 6..10 (чем дальше, тем выше).
  /// Влево → 5..1 (чем дальше, тем ниже).
  /// Вверх/Вниз — НЕТ оценки (просто возврат карточки).
  int ratingForOffset(Offset drag, double velocity) {
    // Только горизонтальный свайп даёт оценку
    if (drag.dx.abs() < drag.dy.abs()) {
      return 0; // Вертикальный свайп — нет оценки
    }
    final t = ((drag.dx.abs() - _commitStart) / (_maxDrag - _commitStart))
        .clamp(0.0, 0.9999);
    if (drag.dx > 0) {
      // Вправо — хорошие: 6..10
      return (6 + (t * 5).floor()).clamp(1, 10);
    } else {
      // Влево — плохие: 5..1
      return (5 - (t * 5).floor()).clamp(1, 10);
    }
  }

  /// Определяет сторону свайпа: +1 = вправо, -1 = влево.
  /// Возвращает 0 для вертикальных свайпов (нет оценки).
  int _sideOf(Offset drag) {
    if (drag.dx.abs() < drag.dy.abs()) {
      return 0; // Вертикальный свайп — нет оценки
    }
    return drag.dx >= 0 ? 1 : -1;
  }

  int? get _liveRating {
    if (_phase != _DeckPhase.dragging) return null;
    // Вертикальный свайп — нет оценки
    if (_drag.dx.abs() < _drag.dy.abs()) return null;
    if (_drag.dx.abs() < _commitStart * 0.55) return null;
    return ratingForOffset(_drag, 0);
  }

  void _fly(int rating) {
    if (rating == 0) {
      // Вертикальный свайп — просто возвращаем карточку
      _animateTo(Offset.zero, Curves.easeOutBack, _DeckPhase.returning);
      return;
    }
    _pendingRating = rating;
    final dir = _sideOf(_drag);
    final dirVec = dir > 0 ? const Offset(1, -0.35) : const Offset(-1, 0.35);
    _animateTo(
      Offset(dirVec.dx * _w * 1.3, dirVec.dy * _w * 1.3 + _drag.dy * 0.3),
      Curves.easeOutCubic,
      _DeckPhase.flying,
    );
  }

  void programmaticRate(int rating) {
    if (_busy || widget.assets.isEmpty) return;
    HapticFeedback.mediumImpact();
    _fly(rating.clamp(1, 10));
  }

  Future<void> programmaticSkip() async {
    if (_busy || widget.assets.isEmpty) return;
    HapticFeedback.lightImpact();
    _animateTo(
      Offset(0, _h * 0.5),
      Curves.easeOutCubic,
      _DeckPhase.skipping,
    );
  }

  @override
  Widget build(BuildContext context) {
    final assets = widget.assets;
    if (assets.isEmpty) return const SizedBox.shrink();

    final visibleCount = math.min(assets.length, 3);

    final double settleT;
    if (_phase == _DeckPhase.flying || _phase == _DeckPhase.skipping) {
      settleT = Curves.easeOut.transform(_ctrl.value);
    } else {
      settleT = 0;
    }

    final children = <Widget>[];

    for (var i = visibleCount - 1; i >= 0; i--) {
      final asset = assets[i];
      final isFront = i == 0;

      final depth = isFront ? 0.0 : i - settleT;
      final scale = 1 - 0.05 * depth;

      Widget card = Padding(
        padding: const EdgeInsets.all(16),
        child: Transform.translate(
          offset: Offset(0, -14 * depth),
          child: Transform.scale(
            scale: scale,
            child: _CardView(asset: asset),
          ),
        ),
      );

      if (isFront) {
        final rating = _liveRating;
        final dx = _drag.dx;
        final showHint = rating != null && _phase == _DeckPhase.dragging;
        final hintT = showHint
            ? (((dx.abs() - _commitStart * 0.55) /
                    (_maxDrag - _commitStart * 0.55)))
                .clamp(0.15, 1.0)
            : 0.0;

        card = Transform.translate(
          offset: _drag,
          child: Transform.rotate(
            angle: _angleFor(dx),
            alignment: Alignment.center,
            child: Stack(
              fit: StackFit.expand,
              children: [
                card,
                if (showHint)
                  _RatingBadge(
                    rating: rating,
                    opacity: hintT,
                  ),
              ],
            ),
          ),
        );

        card = GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          onPanCancel: _onPanCancel,
          // Тап по фото — рассмотреть крупно. Оценку он не ставит: тап
          // без перетаскивания не вызывает onPanEnd.
          onTap: () => openPhotoViewer(context, asset),
          onLongPress: () {
            HapticFeedback.heavyImpact();
            programmaticSkip();
          },
          child: card,
        );
      } else {
        card = IgnorePointer(child: card);
      }

      children.add(card);
    }

    return Stack(
      fit: StackFit.expand,
      children: children,
    );
  }

  double _angleFor(double dx) {
    if (dx.abs() < 1) return 0;
    final t = (dx / _w).clamp(-1.0, 1.0);
    return t * _maxAngle;
  }
}

class _RatingBadge extends StatelessWidget {
  const _RatingBadge({
    required this.rating,
    required this.opacity,
  });

  final int rating;
  final double opacity;

  static const _emoji = RatingStyle.emoji;

  static Color _colorFor(int r) => RatingStyle.color(r);

  @override
  Widget build(BuildContext context) {
    final emoji = _emoji[rating];
    final color = _colorFor(rating);
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Transform.rotate(
            angle: rating >= 6 ? -0.18 : 0.18,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white, width: 5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: emoji != null
                  ? Text(
                      emoji,
                      style: const TextStyle(fontSize: 72),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$rating',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 84,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '/10',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardView extends StatelessWidget {
  const _CardView({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surfaceContainerLow),
          AssetThumbImage(asset: asset),
          if (asset.type == AssetType.video)
            Align(
              alignment: Alignment.bottomLeft,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          // Дата снимка: по ней видно, что перед тобой — свежее фото или
          // четырёхлетний размытый кадр из отпуска. Без неё решение
          // «оставить или удалить» принимается вслепую.
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _formatDate(asset.createDateTime),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Дата в формате ДД.ММ.ГГГГ.
  static String _formatDate(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day.$month.${d.year}';
  }
}

class AssetThumbImage extends StatefulWidget {
  const AssetThumbImage({
    super.key,
    required this.asset,
    this.thumbnailSize = 1200,
  });

  final AssetEntity asset;
  final int thumbnailSize;

  @override
  State<AssetThumbImage> createState() => _AssetThumbImageState();
}

class _AssetThumbImageState extends State<AssetThumbImage> {
  late Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final s = widget.thumbnailSize;
    _future = widget.asset
        .thumbnailDataWithSize(ThumbnailSize(s, s))
        .then<Uint8List?>((v) => v)
        .catchError((_) => null);
  }

  @override
  void didUpdateWidget(covariant AssetThumbImage oldWidget) {
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
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        );
      },
    );
  }
}
