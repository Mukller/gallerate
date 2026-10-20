import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/core/rating_style.dart';

void main() {
  group('RatingStyle.color', () {
    test('все 10 оценок имеют свой цвет', () {
      for (var r = 1; r <= 10; r++) {
        expect(RatingStyle.color(r), isNot(Colors.grey),
            reason: 'оценка $r должна иметь собственный цвет');
      }
    });

    test('цвета уникальны (нет визуальных дублей)', () {
      final seen = <Color>{};
      for (var r = 1; r <= 10; r++) {
        seen.add(RatingStyle.color(r));
      }
      expect(seen.length, 10);
    });

    test('вне диапазона — серый', () {
      expect(RatingStyle.color(0), Colors.grey);
      expect(RatingStyle.color(11), Colors.grey);
    });
  });

  group('RatingStyle.emoji', () {
    test('эмодзи только у крайних оценок', () {
      expect(RatingStyle.emojiFor(10), isNotNull);
      expect(RatingStyle.emojiFor(1), isNotNull);
      for (var r = 2; r <= 9; r++) {
        expect(RatingStyle.emojiFor(r), isNull, reason: 'оценка $r');
      }
    });
  });

  group('RatingStyle пороги', () {
    test('6..10 — оставить', () {
      for (var r = 6; r <= 10; r++) {
        expect(RatingStyle.isKeep(r), isTrue, reason: '$r');
      }
    });

    test('1..5 — на удаление', () {
      for (var r = 1; r <= 5; r++) {
        expect(RatingStyle.isDelete(r), isTrue, reason: '$r');
        expect(RatingStyle.isKeep(r), isFalse, reason: '$r');
      }
    });

    test('0 (пропуск) не удаляется и не оставляется', () {
      expect(RatingStyle.isKeep(0), isFalse);
      expect(RatingStyle.isDelete(0), isFalse);
    });
  });

  testWidgets('бейдж показывает оценку', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RatingStyle.badge(7)),
      ),
    );
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('RatingEditSheet предлагает 10 вариантов', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => RatingEditSheet.show(context, 4),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 10 кнопок выбора оценки
    for (var r = 1; r <= 10; r++) {
      final emoji = RatingStyle.emojiFor(r);
      if (emoji == null) {
        expect(find.text('$r'), findsWidgets, reason: 'кнопка $r');
      }
    }
    expect(find.byType(RatingEditSheet), findsOneWidget);
  });
}
