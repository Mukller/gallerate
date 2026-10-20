import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'logic/app_state.dart';
import 'ui/onboarding/onboarding_screen.dart';
import 'ui/permission/permission_screen.dart';
import 'ui/root_shell.dart';

class GallerateApp extends StatelessWidget {
  const GallerateApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    Locale? locale;
    if (state.localeCode != null) {
      locale = Locale(state.localeCode!);
    }

    return MaterialApp(
      title: 'Gallerate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: state.themeMode,
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ru')],
      home: const _HomeRouter(),
    );
  }
}

class _HomeRouter extends StatelessWidget {
  const _HomeRouter();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    switch (state.phase) {
      case BootPhase.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case BootPhase.needsOnboarding:
        return const OnboardingScreen();
      case BootPhase.needsPermission:
        return const PermissionScreen();
      case BootPhase.ready:
        return const RootShell();
    }
  }
}
