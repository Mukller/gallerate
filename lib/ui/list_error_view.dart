import 'package:flutter/material.dart';

import '../core/l10n.dart';

/// Экран ошибки загрузки списка.
///
/// [FutureBuilder] не различает «ещё грузится» и «упало с ошибкой»:
/// при ошибке `hasData` тоже ложно, и экран навсегда оставался с
/// вращающимся индикатором — без текста и без возможности повторить.
/// Этот виджет показывает, что именно случилось, и даёт повторить.
class ListErrorView extends StatelessWidget {
  const ListErrorView({super.key, required this.onRetry, this.detail});

  /// Повторить загрузку.
  final VoidCallback onRetry;

  /// Техническая подробность ошибки (для тех, кто смотрит лог).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 64, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(
              context.tr('listError'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('retry')),
            ),
          ],
        ),
      ),
    );
  }
}
