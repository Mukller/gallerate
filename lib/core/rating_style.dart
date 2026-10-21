import 'package:flutter/material.dart';

import '../data/models.dart' show isDeleteRating, isKeepRating;

/// Единый источник правды для отображения оценок 1..10.
///
/// Раньше `_colorFor` и `_emoji` были продублированы в swipe_screen,
/// best_screen, stats_screen и card_deck — с расхождением (в card_deck
/// была отдельная, более точная палитра). Теперь одна реализация.
class RatingStyle {
  RatingStyle._();

  static const Color _bad = Color(0xFFD84315);
  static const Color _poor = Color(0xFFEF6C00);
  static const Color _mid = Color(0xFFC0CA33);
  static const Color _good = Color(0xFF43A047);
  static const Color _great = Color(0xFF00897B);
  static const Color _top = Color(0xFF6A1B9A);

  /// Полная палитра 1..10 — для графиков и бейджей с номером.
  static const Map<int, Color> palette = {
    1: Color(0xFFB71C1C),
    2: _bad,
    3: _poor,
    4: Color(0xFFF9A825),
    5: _mid,
    6: Color(0xFF7CB342),
    7: _good,
    8: _great,
    9: Color(0xFF00838F),
    10: _top,
  };

  /// Группированный цвет: 1–2 / 3–4 / 5 / 6–7 / 8–9 / 10.
  static Color color(int rating) => palette[rating] ?? Colors.grey;

  static const Map<int, String> emoji = {10: '🔥', 1: '💩'};

  static String? emojiFor(int rating) => emoji[rating];

  /// Оценка 6..10 — «оставить», 1..5 — «на удаление», 0 — пропуск.
  /// Правило живёт в data/models.dart — там, где его читает и база.
  static bool isKeep(int rating) => isKeepRating(rating);

  static bool isDelete(int rating) => isDeleteRating(rating);

  /// Бейдж оценки поверх миниатюры.
  /// [color] переопределяет цвет шкалы (например, зелёный = уже разложено).
  static Widget badge(
    int rating, {
    double radius = 8,
    double fontSize = 12,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? RatingStyle.color(rating),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        '$rating',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Диалог переоценки уже оценённого фото.
///
/// Раньше оценка была неизменяемой навсегда: ошибился свайпом — исправить
/// было нечем. Теперь из «Лучших» и «Убрать» можно переоценить.
class RatingEditSheet extends StatelessWidget {
  const RatingEditSheet({super.key, required this.current});

  final int current;

  /// Возвращает новую оценку или null, если пользователь отменил.
  static Future<int?> show(BuildContext context, int current) {
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (_) => RatingEditSheet(current: current),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var r = 10; r >= 1; r--)
              _RatingOption(rating: r, selected: r == current),
          ],
        ),
      ),
    );
  }
}

class _RatingOption extends StatelessWidget {
  const _RatingOption({required this.rating, required this.selected});

  final int rating;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = RatingStyle.color(rating);
    final emoji = RatingStyle.emojiFor(rating);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Rate $rating out of 10',
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).pop(rating),
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
            child: emoji != null
                ? ExcludeSemantics(
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  )
                : Text(
                    '$rating',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
