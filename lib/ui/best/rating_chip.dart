import 'package:flutter/material.dart';

import '../../core/rating_style.dart';

/// Чип выбора оценки в «Лучших»: номер/эмодзи + количество фото,
/// подсветка выбранного состояния.
///
/// Вынесен в отдельный файл не ради красоты, а ради тестируемости:
/// именно здесь был баг, когда горизонтальный ListView с `reverse: true`
/// уводил выбранный чип за границу viewport и он рисовался обрезанным.
/// Теперь ряд чипов собирается через [RatingChipRow] (Wrap), где обрезка
/// невозможна по построению, а сам чип можно проверить обычным виджет-тестом
/// без БД и без галереи.
class RatingChip extends StatelessWidget {
  const RatingChip({
    super.key,
    required this.rating,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final int rating;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = RatingStyle.color(rating);
    final emoji = RatingStyle.emojiFor(rating);
    final onColor =
        selected ? Colors.white : Theme.of(context).colorScheme.onSurface;

    return Semantics(
      button: true,
      selected: selected,
      // container: true обязателен — InkWell внутри создаёт собственный
      // узел семантики, и без контейнера наша метка к нему не привяжется.
      container: true,
      label: 'Rating $rating, $count photos',
      child: Material(
        color: selected ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                // У выбранного чипа обводка того же цвета, что и заливка,
                // поэтому её не видно — показываем белым.
                color: selected ? Colors.white : color,
                width: selected ? 2.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (emoji != null)
                  ExcludeSemantics(
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  )
                else
                  Text(
                    '$rating',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: selected ? Colors.white : color,
                    ),
                  ),
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: onColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ряд из всех десяти чипов оценок, от лучших к худшим.
///
/// Именно Wrap, а не горизонтальный скролл: скролл может увести
/// выбранный элемент за границу, и пользователь видит обрезанный чип.
class RatingChipRow extends StatelessWidget {
  const RatingChipRow({
    super.key,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final int selected;
  final Map<int, int> counts;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var rating = 10; rating >= 1; rating--)
          RatingChip(
            key: ValueKey('rating_chip_$rating'),
            rating: rating,
            count: counts[rating] ?? 0,
            selected: rating == selected,
            onTap: () => onSelect(rating),
          ),
      ],
    );
  }
}
