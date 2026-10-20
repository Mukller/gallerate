import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/l10n.dart';
import '../../logic/app_state.dart';
import '../settings/settings_screen.dart';
import '../settings/album_picker_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  int _size = 10;
  TimeOfDay _time = const TimeOfDay(hour: 20, minute: 0);
  List<String> _albumIds = [];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_page < 2) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pages = [
      _IntroPage(
        icon: Icons.auto_awesome_motion_outlined,
        title: context.tr('ob1Title'),
        body: context.tr('ob1Body'),
        color: Theme.of(context).colorScheme.primary,
      ),
      _IntroPage(
        icon: Icons.offline_bolt_outlined,
        title: context.tr('ob2Title'),
        body: context.tr('ob2Body'),
        color: Colors.green.shade600,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  ...pages,
                  _SetupPage(
                    size: _size,
                    time: _time,
                    albumCount: _albumIds.length,
                    granted: app.hasAccess,
                    onSizeChanged: (v) => setState(() => _size = v),
                    onTimePicked: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _time,
                      );
                      if (t != null) setState(() => _time = t);
                    },
                    onPickAlbums: () async {
                      final result =
                          await Navigator.of(context).push<List<String>>(
                        MaterialPageRoute(
                          builder: (_) =>
                              AlbumPickerScreen(initiallySelected: _albumIds),
                        ),
                      );
                      if (result != null) {
                        setState(() => _albumIds = result);
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      final active = i == _page;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  if (_page < 2)
                    FilledButton(
                      onPressed: _next,
                      child: Text(context.tr('ok')),
                    )
                  else
                    FilledButton.icon(
                      onPressed: app.hasAccess
                          ? () async {
                              await app.finishOnboarding(
                                chosenAlbumIds: _albumIds,
                                size: _size,
                                time: _time,
                              );
                              // Спрашиваем только после старта, чтобы
                              // не мешать онбордингу двумя диалогами подряд.
                              await app.requestNotificationPermission();
                            }
                          : null,
                      icon: const Icon(Icons.rocket_launch_outlined),
                      label: Text(context.tr('start')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 84, color: color),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _SetupPage extends StatelessWidget {
  const _SetupPage({
    required this.size,
    required this.time,
    required this.albumCount,
    required this.granted,
    required this.onSizeChanged,
    required this.onTimePicked,
    required this.onPickAlbums,
  });

  final int size;
  final TimeOfDay time;
  final int albumCount;
  final bool granted;
  final ValueChanged<int> onSizeChanged;
  final VoidCallback onTimePicked;
  final VoidCallback onPickAlbums;

  String _fmt(BuildContext context, TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.tune_rounded,
              size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            context.tr('ob3Title'),
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('ob3Body'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('setSizeLabel'),
                      style: Theme.of(context).textTheme.titleSmall),
                  Slider(
                    value: size.toDouble(),
                    min: 5,
                    max: 50,
                    divisions: 45,
                    label: '$size',
                    onChanged: (v) => onSizeChanged(v.round()),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule_rounded),
              title: Text(context.tr('appearTimeLabel')),
              trailing: Text(_fmt(context, time),
                  style: Theme.of(context).textTheme.titleMedium),
              onTap: onTimePicked,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: Text(context.tr('albumsLabel')),
              subtitle: Text(albumCount == 0
                  ? context.tr('albumsValueAll')
                  : context.tr('albumsValueN', {'n': '$albumCount'})),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: onPickAlbums,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                granted
                    ? Icons.check_circle_rounded
                    : Icons.lock_outline_rounded,
                color: granted ? Colors.green.shade600 : null,
              ),
              title: Text(context.tr('permTitle')),
              subtitle: granted ? null : Text(context.tr('permBody')),
              trailing: granted
                  ? null
                  : FilledButton(
                      onPressed: () =>
                          context.read<AppState>().grantPermission(),
                      child: Text(context.tr('permButton')),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
