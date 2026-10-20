import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'logic/app_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const GallerateApp(),
    ),
  );
}
