import 'dart:developer' as developer;

import 'package:cookdex/frame_work_binding.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show recipe, summary;

class _Binding extends AutomatedTestWidgetsFlutterBinding
    with FrameWorkReporting {}

class _Cards {
  final work = CardPreparation();
  final scroll = ScrollController();
  final first = <int, int>{};
  final stages = <int, int>{};
  final history = <int, List<int>>{};
  final recipes = <RecipeSummary>[
    for (var i = 0; i < 500; i++)
      summary(recipe('$i', title: 'Garden soup $i')),
  ];
}

Future<_Cards> _mount(
  WidgetTester tester, {
  int columns = 3,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1024, 600);
  final cards = _Cards();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    cards.work.dispose();
    cards.scroll.dispose();
    tester.view.reset();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme().copyWith(platform: platform),
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, size) {
            cards.work.configure(
              context,
              cards.recipes,
              size.maxWidth / columns,
              grid: true,
              fixedHeight: 178,
              columns: columns,
            );
            return ProgressiveCards(
              preparation: cards.work,
              controller: cards.scroll,
              child: ListView.builder(
                controller: cards.scroll,
                physics: const ClampingScrollPhysics(),
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                itemExtent: 188,
                itemCount: cards.recipes.length ~/ columns,
                itemBuilder: (context, row) => Row(
                  children: [
                    for (var column = 0; column < columns; column++)
                      Expanded(
                        child: ProgressiveCard(
                          key: ValueKey(row * columns + column),
                          recipe: cards.recipes[row * columns + column],
                          grid: true,
                          builder: (context, stage, geometry) {
                            final index = row * columns + column;
                            cards.first.putIfAbsent(index, () => stage);
                            cards.stages[index] = stage;
                            final history = cards.history.putIfAbsent(
                              index,
                              () => [],
                            );
                            if (history.isEmpty || history.last != stage) {
                              history.add(stage);
                            }
                            return SizedBox(
                              height: 178,
                              child: Column(
                                children: [
                                  Text(cards.recipes[index].title),
                                  if (stage >= 1)
                                    const Text('A warming family supper'),
                                  if (stage >= 2)
                                    const Text('Serves 4 · 30 min'),
                                  if (stage >= 3) const Text('Dinner'),
                                  if (stage >= 4)
                                    const Icon(Icons.star_outline),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cards;
}

void main() {
  final binding = _Binding();
  tearDown(() => FrameWorkReporting.onFrameWork = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final columns in [1, 2, 3]) {
      testWidgets(
        'spare moving frame admission on $platform, $columns columns',
        (tester) async {
          FrameWorkReporting.onFrameWork = (_, _) {};
          final cards = await _mount(
            tester,
            platform: platform,
            columns: columns,
          );
          final finger = await tester.startGesture(const Offset(400, 450));
          await finger.moveBy(const Offset(0, -24));
          await tester.pump(const Duration(milliseconds: 16));
          final before = cards.first.keys.toSet();
          await finger.moveBy(const Offset(0, -600));
          await tester.pump(const Duration(milliseconds: 16));
          final added = cards.first.keys.toSet().difference(before);
          final complete = added.where((i) => cards.first[i] == 4).length;
          expect(added.length, greaterThanOrEqualTo(3));
          expect(cards.scroll.position.isScrollingNotifier.value, isTrue);
          expect(
            complete,
            platform == TargetPlatform.android && columns > 1
                ? inInclusiveRange(1, columns)
                : 0,
          );
          await finger.cancel();
        },
        semanticsEnabled: false,
      );
    }
  }

  testWidgets('single-column Android fills one stage at a time while moving', (
    tester,
  ) async {
    FrameWorkReporting.onFrameWork = (_, _) {};
    final cards = await _mount(tester, columns: 1);
    final finger = await tester.startGesture(const Offset(400, 450));
    await finger.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 16));
    final before = cards.first.keys.toSet();
    await finger.moveBy(const Offset(0, -600));
    await tester.pump(const Duration(milliseconds: 16));
    final added = cards.first.keys.toSet().difference(before);
    expect(added, isNotEmpty);
    expect(added.every((i) => cards.first[i] == 0), isTrue);
    for (var frame = 0; frame < 32; frame++) {
      await finger.moveBy(const Offset(0, -1));
      await tester.pump(const Duration(milliseconds: 16));
      expect(cards.scroll.position.isScrollingNotifier.value, isTrue);
    }
    final finished = added.where((i) => cards.stages[i] == 4);
    expect(finished, isNotEmpty);
    for (final index in finished) {
      expect(cards.history[index], [0, 1, 2, 3, 4]);
    }
    await finger.cancel();
  }, semanticsEnabled: false);

  testWidgets('busy animation frame defers cards, then fills during movement', (
    tester,
  ) async {
    FrameWorkReporting.onFrameWork = (_, _) {};
    final cards = await _mount(tester);
    final finger = await tester.startGesture(const Offset(400, 450));
    await finger.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 16));
    final before = cards.first.keys.toSet();
    await finger.moveBy(const Offset(0, -600));
    binding.scheduleFrameCallback((_) {
      final start = developer.Timeline.now;
      while (developer.Timeline.now - start < 20000) {}
    });
    await tester.pump(const Duration(milliseconds: 16));
    final added = cards.first.keys.toSet().difference(before);
    expect(added, isNotEmpty);
    expect(added.every((i) => cards.first[i] == 0), isTrue);
    for (var frame = 0; frame < 20; frame++) {
      await finger.moveBy(const Offset(0, -1));
      await tester.pump(const Duration(milliseconds: 16));
      expect(cards.scroll.position.isScrollingNotifier.value, isTrue);
    }
    expect(added.every((i) => cards.stages[i] == 4), isTrue);
    await finger.cancel();
  }, semanticsEnabled: false);

  for (final (columns, expected) in [(1, 14), (2, 28), (3, 39)]) {
    testWidgets(
      'preparation uses actual height and $columns columns within 48 cards',
      (tester) async {
        final cards = await _mount(tester, columns: columns);
        final prepared = cards.recipes
            .where((r) => cards.work.geometry.prepared(r) != null)
            .toList();
        // Four visible 188dp rows, then ceil(3 * 600 / 188) rows ahead.
        expect(prepared.length, expected);
        expect(prepared.length, lessThanOrEqualTo(48));
      },
      semanticsEnabled: false,
    );
  }
}
