import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/l10n.dart';
import '../data/rating_store.dart';
import '../logic/app_state.dart';
import 'best/best_screen.dart';
import 'cleanup/cleanup_screen.dart';
import 'history/history_screen.dart';
import 'settings/settings_screen.dart';
import 'stats/stats_screen.dart';
import 'swipe/swipe_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key, this.store});

  /// Хранилище оценок, которое получают все экраны оболочки.
  /// По умолчанию — боевая база. Параметр существует не только для тестов:
  /// раньше экраны создавались как `const` и молча тянули глобальный
  /// `AppDb.instance`, из-за чего дерево целиком было непроверяемым —
  /// виджет-тест падал на «databaseFactory is only initialized when using
  /// sqflite».
  final RatingStore? store;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with WidgetsBindingObserver {
  int _index = 0;
  Timer? _ticker;

  late final List<Widget> _screens = [
    const SwipeScreen(),
    BestScreen(store: widget.store),
    CleanupScreen(store: widget.store),
    HistoryScreen(store: widget.store),
    StatsScreen(store: widget.store),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Сет генерировался только при запуске приложения. Если пользователь
  /// держал приложение открытым через момент появления — сет не появлялся
  /// до перезапуска. Раз в минуту и при возврате в foreground проверяем.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        context.read<AppState>().ensureTodaySet();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final app = context.read<AppState>();
      // Разрешение могли выдать в настройках, а время сет уже наступило.
      unawaited(app.recheckPermission());
      unawaited(app.ensureTodaySet());
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    final titles = [
      context.tr('tabSwipe'),
      context.tr('tabBest'),
      context.tr('tabCleanup'),
      context.tr('tabHistory'),
      context.tr('tabStats'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          IconButton(
            tooltip: context.tr('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Provider<int>.value(
        value: _index,
        child: IndexedStack(index: _index, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.style_outlined),
            selectedIcon: const Icon(Icons.style),
            label: titles[0],
          ),
          NavigationDestination(
            icon: const Icon(Icons.favorite_outline),
            selectedIcon: const Icon(Icons.favorite),
            label: titles[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.delete_sweep_outlined),
            selectedIcon: const Icon(Icons.delete_sweep),
            label: titles[2],
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: titles[3],
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            label: titles[4],
          ),
        ],
      ),
    );
  }
}
