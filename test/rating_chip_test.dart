import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/ui/best/rating_chip.dart';

Widget host(Widget child, {double width = 400}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  group('RatingChip', () {
    testWidgets('показывает номер оценки и количество', (tester) async {
      await tester.pumpWidget(host(const RatingChip(
        rating: 7,
        count: 3,
        selected: false,
        onTap: _noop,
      )));

      expect(find.text('7'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('у 1 и 10 показывает эмодзи вместо номера', (tester) async {
      await tester.pumpWidget(host(const RatingChip(
        rating: 10,
        count: 1,
        selected: false,
        onTap: _noop,
      )));
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('10'), findsNothing);

      await tester.pumpWidget(host(const RatingChip(
        rating: 1,
        count: 2,
        selected: false,
        onTap: _noop,
      )));
      expect(find.text('💩'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('тап вызывает onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(host(RatingChip(
        rating: 5,
        count: 0,
        selected: false,
        onTap: () => tapped = true,
      )));

      await tester.tap(find.byType(RatingChip));
      expect(tapped, isTrue);
    });

    testWidgets('имеет ненулевой размер — не схлопнут', (tester) async {
      await tester.pumpWidget(host(const RatingChip(
        rating: 6,
        count: 12,
        selected: false,
        onTap: _noop,
      )));

      final size = tester.getSize(find.byType(RatingChip));
      expect(size.width, greaterThan(20));
      expect(size.height, greaterThan(20));
    });

    testWidgets('выбранный чип шире невыбранного за счёт обводки',
        (tester) async {
      await tester.pumpWidget(host(const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RatingChip(rating: 6, count: 0, selected: true, onTap: _noop),
          SizedBox(height: 8),
          RatingChip(rating: 6, count: 0, selected: false, onTap: _noop),
        ],
      )));

      final selectedSize = tester.getSize(find.byType(RatingChip).at(0));
      final plainSize = tester.getSize(find.byType(RatingChip).at(1));
      expect(selectedSize.width, greaterThan(plainSize.width),
          reason: 'у выбранного обводка 2.5 против 1');
    });

    testWidgets('доступен скринридеру с описанием', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(const RatingChip(
        rating: 8,
        count: 5,
        selected: false,
        onTap: _noop,
      )));

      // Проверяем через узел семантики самого чипа: finder по метке
      // не находит её, когда внутри есть InkWell со своим узлом.
      final node = tester.getSemantics(find.byType(RatingChip));
      expect(node.label, contains('Rating 8'));
      expect(node.label, contains('5 photos'));
      handle.dispose();
    });
  });

  group('RatingChipRow', () {
    testWidgets('строит все десять чипов', (tester) async {
      await tester.pumpWidget(host(const RatingChipRow(
        selected: 10,
        counts: {},
        onSelect: _noopInt,
      )));

      expect(find.byType(RatingChip), findsNWidgets(10));
      for (var r = 1; r <= 10; r++) {
        expect(find.byKey(ValueKey('rating_chip_$r')), findsOneWidget,
            reason: 'чип $r должен существовать');
      }
    });

    testWidgets('идёт от лучших к худшим', (tester) async {
      await tester.pumpWidget(host(const RatingChipRow(
        selected: 10,
        counts: {},
        onSelect: _noopInt,
      )));

      final chips = tester.widgetList<RatingChip>(find.byType(RatingChip));
      expect(
          chips.map((c) => c.rating).toList(), [10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
    });

    // Регрессия: ряд собирался горизонтальным ListView с reverse: true,
    // и выбранный по умолчанию рейтинг 10 оказывался за границей
    // viewport — рисовался обрезанным, без эмодзи и без номера.
    testWidgets('выбранный чип полностью попадает в родителя', (tester) async {
      const width = 380.0;
      await tester.pumpWidget(host(
        const RatingChipRow(
          selected: 10,
          counts: {10: 2, 8: 1, 7: 1},
          onSelect: _noopInt,
        ),
        width: width,
      ));

      final selectedFinder = find.byKey(const ValueKey('rating_chip_10'));
      expect(selectedFinder, findsOneWidget);

      // Чип не обрезан: он целиком внутри отведённой ширины.
      final size = tester.getSize(selectedFinder);
      final topLeft = tester.getTopLeft(selectedFinder);
      expect(topLeft.dx, greaterThanOrEqualTo(-0.01));
      expect(topLeft.dx + size.width, lessThanOrEqualTo(width + 0.01));

      // И содержимое видно: у 10 — эмодзи и число фото.
      expect(find.text('🔥'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('выбран ровно один чип', (tester) async {
      await tester.pumpWidget(host(const RatingChipRow(
        selected: 6,
        counts: {},
        onSelect: _noopInt,
      )));

      final chips = tester.widgetList<RatingChip>(find.byType(RatingChip));
      expect(chips.where((c) => c.selected).map((c) => c.rating), [6]);
    });

    testWidgets('выбор сообщает выбранную оценку', (tester) async {
      int? picked;
      await tester.pumpWidget(host(RatingChipRow(
        selected: 10,
        counts: const {},
        onSelect: (v) => picked = v,
      )));

      await tester.tap(find.byKey(const ValueKey('rating_chip_4')));
      expect(picked, 4);
    });

    testWidgets('переносы на второй ряд не обрезают элементы', (tester) async {
      // Узкая ширина заставляет Wrap перенести часть чипов на второй ряд.
      await tester.pumpWidget(host(
        const RatingChipRow(
          selected: 3,
          counts: {},
          onSelect: _noopInt,
        ),
        width: 200,
      ));

      expect(find.byType(RatingChip), findsNWidgets(10));
      for (var r = 1; r <= 10; r++) {
        final finder = find.byKey(ValueKey('rating_chip_$r'));
        final size = tester.getSize(finder);
        expect(size.width, greaterThan(0),
            reason: 'чип $r не должен схлопнуться при переносе');
        expect(size.height, greaterThan(0));
      }
    });
  });
}

void _noop() {}

void _noopInt(int _) {}
