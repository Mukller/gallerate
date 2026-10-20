import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gallerate/core/theme.dart';

void main() {
  testWidgets('light theme renders a scaffold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SizedBox()),
      ),
    );
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
