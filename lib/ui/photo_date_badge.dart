import 'package:flutter/material.dart';

/// Дата съёмки в формате ДД.ММ.ГГГГ.
String formatPhotoDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  return '$day.$month.${d.year}';
}

/// Плашка с датой съёмки поверх миниатюры.
///
/// Сортировка «по дате съёмки» имеет смысл, только если дату видно:
/// иначе «старые кадры сверху» — это утверждение, которое пользователь
/// может только принять на веру.
class PhotoDateBadge extends StatelessWidget {
  const PhotoDateBadge({super.key, required this.takenAt});

  /// Когда сделан снимок (мс с эпохи). null — дата неизвестна:
  /// так бывает у фото, оценённых до появления этого поля.
  final int? takenAt;

  @override
  Widget build(BuildContext context) {
    final ms = takenAt;
    if (ms == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        formatPhotoDate(DateTime.fromMillisecondsSinceEpoch(ms)),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
