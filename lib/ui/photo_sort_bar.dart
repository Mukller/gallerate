import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../data/models.dart';

/// Панель переключения порядка: по оценке или по дате съёмки.
///
/// Раньше такая панель была продублирована в «Убрать» и в «Лучших» —
/// вместе с состоянием, переключением и вызовом запроса. Одно место
/// означает одно поведение: если правило поменяется, поменяется везде.
class PhotoSortBar extends StatelessWidget {
  const PhotoSortBar({
    super.key,
    required this.sort,
    required this.onToggle,
    this.showLabel = true,
  });

  /// Текущий порядок.
  final PhotoSort sort;

  /// Переключить порядок.
  final VoidCallback onToggle;

  /// Показывать ли текст с текущим порядком.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final byDate = sort == PhotoSort.takenDate;
    final button = IconButton(
      onPressed: onToggle,
      icon: Icon(byDate ? Icons.event : Icons.star_outline),
      tooltip: context.tr('sortToggle'),
      visualDensity: VisualDensity.compact,
    );
    // Без подписи отдаём одну кнопку, а не Row с Spacer: панель ставят
    // и в строку без ограниченной ширины, и Spacer там вызывает
    // «RenderFlex children have non-zero flex but incoming width
    // constraints are unbounded».
    if (!showLabel) return button;
    return Row(
      children: [
        Expanded(
          child: Text(
            byDate ? context.tr('sortOldestFirst') : context.tr('sortByRating'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        button,
      ],
    );
  }
}
