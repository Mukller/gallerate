import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../data/db.dart';
import '../../data/rating_store.dart';
import '../../logic/app_state.dart';
import 'album_picker_screen.dart';

export 'album_picker_screen.dart';

/// Версия приложения. Держится здесь одной строкой и сверяется тестом
/// с pubspec.yaml — раньше в интерфейсе было написано 0.3.0, пока в
/// pubspec уже стояло 0.4.0+4, и пользователь видел устаревшую версию.
const String appVersion = '0.5.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.store});

  /// Хранилище оценок — нужно для экспорта и импорта. По умолчанию боевая
  /// база; в тестах подставляется фейк (см. комментарий в [BestScreen.store]).
  final RatingStore? store;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  RatingStore get _store => widget.store ?? AppDb.instance;

  static const _fileName = 'gallerate-ratings.json';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickAlbums(AppState app) async {
    final result = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => AlbumPickerScreen(initiallySelected: app.albumIds),
      ),
    );
    if (result != null) await app.setAlbumsAndSave(result);
  }

  Future<void> _pickTime(AppState app) async {
    final initial = TimeOfDay(
      hour: app.appearMinutes ~/ 60,
      minute: app.appearMinutes % 60,
    );
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t != null) await app.setAppearTime(t);
  }

  Future<void> _exportRatings() async {
    if (_busy) return;
    // Локализованные строки готовим ДО await: после await контекст
    // уже нельзя трогать без проверки mounted.
    final nothing = context.tr('nothingToExport');
    final exported = context.tr('exported');
    final failed = context.tr('exportFailed');
    setState(() => _busy = true);
    try {
      final rows = await _store.allRatingMaps();
      if (rows.isEmpty) {
        _toast(nothing);
        return;
      }
      final payload = {
        'app': 'gallerate',
        'version': 1,
        'exported_at': DateTime.now().toIso8601String(),
        'ratings': rows,
      };
      // Системный диалог сохранения: пользователь сам выбирает папку.
      final path = await FilePicker.platform.saveFile(
        dialogTitle: exported,
        fileName: _fileName,
        type: FileType.any,
      );
      if (path == null) return; // пользователь отменил
      await File(path).writeAsString(jsonEncode(payload));
      _toast(exported);
    } catch (e) {
      _toast(L10n.fill(failed, {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importRatings() async {
    if (_busy) return;
    final importFailed = context.tr('importFailed');
    final importedTpl = context.tr('imported');
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      // Системный диалог открытия файла.
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return; // отменил
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        _toast(L10n.fill(importFailed, {'error': 'cannot read file'}));
        return;
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      final raw = (decoded is Map ? decoded['ratings'] : decoded);
      if (raw is! List) {
        _toast(L10n.fill(importFailed, {'error': 'bad format'}));
        return;
      }
      final rows = <Map<String, Object?>>[];
      for (final item in raw) {
        if (item is Map<String, Object?>) rows.add(item);
      }
      final (added, updated) = await _store.upsertRatings(rows);
      if (!mounted) return;
      await app.refreshCollections();
      _toast(L10n.fill(importedTpl, {
        'imported': '$added',
        'updated': '$updated',
      }));
    } catch (e) {
      _toast(L10n.fill(importFailed, {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearRatings() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('clearRatingsTitle')),
        content: Text(ctx.tr('clearRatingsBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('clearRatings')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cleared = context.tr('ratingsCleared');
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      await app.clearRatings();
      _toast(cleared);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reshuffle() async {
    if (_busy) return;
    final reshuffledTpl = context.tr('reshuffled');
    final app = context.read<AppState>();
    setState(() => _busy = true);
    try {
      final n = await app.markAllUnsorted();
      _toast(L10n.fill(reshuffledTpl, {'n': '$n'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetEverything() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('resetConfirmTitle')),
        content: Text(ctx.tr('resetConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('resetLabel')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AppState>().resetAll();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final lang = app.localeCode ?? 'sys';

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionHeader(context.tr('themeLabel')),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                icon: const Icon(Icons.brightness_auto_outlined),
                label: Text(context.tr('themeSystem')),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: const Icon(Icons.light_mode_outlined),
                label: Text(context.tr('themeLight')),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: const Icon(Icons.dark_mode_outlined),
                label: Text(context.tr('themeDark')),
              ),
            ],
            selected: {app.themeMode},
            onSelectionChanged: (s) => app.setThemeModeAndSave(s.first),
          ),
          const SizedBox(height: 20),
          _SectionHeader(context.tr('langLabel')),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'sys',
                label: Text(context.tr('langSystem')),
              ),
              const ButtonSegment(value: 'en', label: Text('English')),
              const ButtonSegment(value: 'ru', label: Text('Русский')),
            ],
            selected: {lang},
            onSelectionChanged: (s) => app.setLocaleAndSave(
              s.first == 'sys' ? null : s.first,
            ),
          ),
          const SizedBox(height: 20),
          _SectionHeader(context.tr('setSizeLabel')),
          Slider(
            value: app.dailyCount.toDouble(),
            min: 5,
            max: 50,
            divisions: 45,
            label: '${app.dailyCount}',
            onChanged: (v) => app.setDailyCountAndSave(v.round()),
          ),
          Center(
            child: Text(
              '${app.dailyCount} ${context.tr('photosUnit')}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: Text(context.tr('appearTimeLabel')),
              trailing: Text(
                app.appearTimeString,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              onTap: () => _pickTime(app),
            ),
          ),
          const SizedBox(height: 8),
          // Уведомления выключены: без этого пользователь считал бы, что
          // ежедневное напоминание настроено, а оно не приходило бы.
          if (app.notificationsOff) ...[
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.notifications_off_outlined,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.tr('notifPermTitle'),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('notifPermBody'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final ok = await app.requestNotificationPermission();
                          if (ok && context.mounted) {
                            await app.syncNotification();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(context.tr('notifEnabled'))),
                              );
                            }
                          }
                        },
                        child: Text(context.tr('allowNotifications')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: Text(context.tr('albumsLabel')),
              subtitle: Text(
                app.albumIds.isEmpty
                    ? context.tr('albumsValueAll')
                    : context
                        .tr('albumsValueN', {'n': '${app.albumIds.length}'}),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickAlbums(app),
            ),
          ),
          const SizedBox(height: 24),
          _SectionHeader(context.tr('ratingsSection')),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.download_rounded,
            label: context.tr('exportRatings'),
            onPressed: _busy ? null : _exportRatings,
          ),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.upload_rounded,
            label: context.tr('importRatings'),
            onPressed: _busy ? null : _importRatings,
          ),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.refresh_rounded,
            label: context.tr('reshuffle'),
            onPressed: _busy ? null : _reshuffle,
          ),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.delete_sweep_outlined,
            label: context.tr('clearRatings'),
            color: Theme.of(context).colorScheme.error,
            onPressed: _busy ? null : _clearRatings,
          ),
          const SizedBox(height: 24),
          _ActionButton(
            icon: Icons.restart_alt_rounded,
            label: context.tr('resetLabel'),
            color: Theme.of(context).colorScheme.error,
            onPressed: _busy ? null : _resetEverything,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              '${context.tr('version')} $appVersion',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side: BorderSide(color: c),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
