import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gallerate/ui/swipe/card_deck.dart';
import 'package:photo_manager/photo_manager.dart';

AssetEntity fakeAsset(String id) {
  return AssetEntity(
    id: id,
    typeInt: 1,
    width: 100,
    height: 100,
  );
}

void main() {
  testWidgets('SwipeCardDeck builds', (tester) async {
    final key = GlobalKey<SwipeCardDeckState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeCardDeck(
            key: key,
            assets: [
              fakeAsset('a'),
              fakeAsset('b'),
            ],
            onRated: (_) {},
            onSkip: () {},
          ),
        ),
      ),
    );

    expect(find.byType(SwipeCardDeck), findsOneWidget);
  });

  testWidgets('programmaticRate fires onRated with exact value',
      (tester) async {
    final ratings = <int>[];
    final key = GlobalKey<SwipeCardDeckState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeCardDeck(
            key: key,
            assets: [fakeAsset('a'), fakeAsset('b')],
            onRated: (r) => ratings.add(r),
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    key.currentState!.programmaticRate(7);
    await tester.pumpAndSettle();
    expect(ratings, [7]);

    key.currentState!.programmaticRate(2);
    await tester.pumpAndSettle();
    expect(ratings, [7, 2]);

    key.currentState!.programmaticRate(10);
    await tester.pumpAndSettle();
    expect(ratings, [7, 2, 10]);
  });

  testWidgets('programmaticSkip fires skip callback', (tester) async {
    var skipCalled = false;
    final key = GlobalKey<SwipeCardDeckState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeCardDeck(
            key: key,
            assets: [fakeAsset('a'), fakeAsset('b')],
            onRated: (_) {},
            onSkip: () => skipCalled = true,
          ),
        ),
      ),
    );
    await tester.pump();

    key.currentState!.programmaticSkip();
    await tester.pumpAndSettle();
    expect(skipCalled, isTrue);
  });

  testWidgets('ratingForOffset maps zones 1..10 for horizontal, 0 for vertical',
      (tester) async {
    final key = GlobalKey<SwipeCardDeckState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeCardDeck(
            key: key,
            assets: [
              fakeAsset('a'),
              fakeAsset('b'),
              fakeAsset('c'),
              fakeAsset('d'),
            ],
            onRated: (_) {},
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    // Right zones (6-10) and left zones (5-1)
    for (var k = 0; k < 5; k++) {
      final mid = 100.0 + 640.0 * ((k + 0.5) / 5);
      expect(key.currentState!.ratingForOffset(Offset(mid, 0), 0), 6 + k,
          reason: 'right zone ${6 + k}');
      expect(key.currentState!.ratingForOffset(Offset(-mid, 0), 0), 5 - k,
          reason: 'left zone ${5 - k}');
    }

    // Vertical swipes should return 0 (no rating)
    expect(key.currentState!.ratingForOffset(const Offset(0, 500), 0), 0,
        reason: 'down swipe returns 0');
    expect(key.currentState!.ratingForOffset(const Offset(0, -500), 0), 0,
        reason: 'up swipe returns 0');
  });

  testWidgets('deck resets when first asset changes', (tester) async {
    final key = GlobalKey<SwipeCardDeckState>();

    var assets = <AssetEntity>[
      fakeAsset('a'),
      fakeAsset('b'),
      fakeAsset('c'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: SwipeCardDeck(
              key: key,
              assets: assets,
              onRated: (_) {},
              onSkip: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    assets = <AssetEntity>[
      fakeAsset('b'),
      fakeAsset('c'),
      fakeAsset('x'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwipeCardDeck(
            key: key,
            assets: assets,
            onRated: (_) {},
            onSkip: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
