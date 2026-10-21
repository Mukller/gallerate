import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/ui/settings/settings_screen.dart';

/// Версия, показанная в настройках, должна совпадать с pubspec.yaml.
///
/// Раньше в интерфейсе было написано 0.3.0, пока в pubspec уже стояло
/// 0.4.0+4: пользователь видел устаревшую версию, и заметить это
/// мог только посторонний, сверяющий два файла.
void main() {
  test('версия в настройках совпадает с pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'в pubspec.yaml нет строки version');

    final pubVersion = m!.group(1)!;
    // pubspec: 0.4.0+4 -> в интерфейсе показываем 0.4.0
    final shown = pubVersion.split('+').first;
    expect(appVersion, shown,
        reason: 'в настройках показана версия $appVersion, '
            'а в pubspec.yaml — $pubVersion');
  });
}
