import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/idle_build_ahead.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show recipe, summary;

const _extent = 220.0;
const _viewport = Key('scheduling-viewport');

class _Harness {
  final preparation = CardPreparation();
  final controller = ScrollController();
  final budget = BuiltRowBudget(32);
  final cacheExtent = ValueNotifier<double>(0);
  final firstStages = <int, List<int>>{};
  final stages = <int, int>{};
  void Function(int index, int stage)? onBuild;
  final recipes = <RecipeSummary>[
    for (var index = 0; index < 500; index++) summary(recipe('$index')),
  ];

  Finder card(int index) =>
      find.byKey(ValueKey(('scheduled-card', index)), skipOffstage: false);

  Set<int> visible(WidgetTester tester) {
    final viewport = tester.getRect(find.byKey(_viewport));
    return {
      for (var index = 0; index < recipes.length; index++)
        if (card(index).evaluate().isNotEmpty &&
            tester.getRect(card(index)).overlaps(viewport) &&
            !_keptAlive(card(index).evaluate().single))
          index,
    };
  }

  int get retained => find
      .byType(KeepBuilt, skipOffstage: false)
      .evaluate()
      .where(_keptAlive)
      .length;
}

bool _keptAlive(Element element) {
  RenderObject? render = element.findRenderObject();
  while (render != null && render.parent is! RenderSliverMultiBoxAdaptor) {
    render = render.parent;
  }
  final data = render?.parentData;
  return data is SliverMultiBoxAdaptorParentData && data.keptAlive;
}

Future<_Harness> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final harness = _Harness();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    harness.controller.dispose();
    harness.cacheExtent.dispose();
    harness.preparation.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(colors: cookdexLightColors),
      home: Scaffold(
        body: Padding(
          // The scheduler must use this viewport, not the whole MediaQuery height.
          padding: const EdgeInsets.only(top: 104, bottom: 140),
          child: ProgressiveCards(
            preparation: harness.preparation,
            controller: harness.controller,
            child: ValueListenableBuilder<double>(
              valueListenable: harness.cacheExtent,
              builder: (context, cacheExtent, _) => ListView.builder(
                key: _viewport,
                controller: harness.controller,
                physics: const ClampingScrollPhysics(),
                scrollCacheExtent: ScrollCacheExtent.pixels(cacheExtent),
                itemExtent: _extent,
                itemCount: harness.recipes.length,
                itemBuilder: (context, index) {
                  var firstBuild = true;
                  return KeepBuilt(
                    key: ValueKey(('retained-row', index)),
                    budget: harness.budget,
                    child: ProgressiveCard(
                      key: ValueKey(('scheduled-card', index)),
                      recipe: harness.recipes[index],
                      grid: true,
                      builder: (context, stage, geometry) {
                        if (firstBuild) {
                          firstBuild = false;
                          harness.firstStages
                              .putIfAbsent(index, () => [])
                              .add(stage);
                        }
                        harness.stages[index] = stage;
                        harness.onBuild?.call(index, stage);
                        // Exercise real native card layout for every scheduler stage.
                        // The inner card is forced only to mirror the outer public
                        // scheduler's stage; the outer scheduler is never overridden.
                        return recipeCardForTest(
                          harness.recipes[index],
                          grid: true,
                          stage: stage,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var frame = 0; frame < count; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('one expensive fill does not starve later moving cards', (
    tester,
  ) async {
    final harness = await _mount(tester);
    int? delayedCard;
    harness.onBuild = (index, stage) {
      if (stage != 1 || delayedCard != null) return;
      delayedCard = index;
      // The scheduler measures wall time between its frame callbacks, so a
      // fake-clock pump cannot supply this one anomalous fill-stage sample.
      final delay = Stopwatch()..start();
      while (delay.elapsedMicroseconds < 15000) {}
      delay.stop();
    };
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_viewport)),
    );
    await finger.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 16));
    await finger.moveBy(const Offset(0, -660));
    harness.preparation.speed = 500;
    await tester.pump(const Duration(milliseconds: 16));
    final shells = harness
        .visible(tester)
        .where((index) => harness.firstStages[index]!.last == 0)
        .toSet();
    expect(shells.length, greaterThanOrEqualTo(2));
    // Keep actual drag activity and nonzero public motion input throughout;
    // a rest-time unconditional fill must not rescue a poisoned predictor.
    for (var frame = 0; frame < 90; frame++) {
      final before = harness.controller.offset;
      await finger.moveBy(const Offset(0, -1));
      harness.preparation.speed = 500;
      await tester.pump(const Duration(milliseconds: 16));
      expect(harness.controller.offset, greaterThan(before));
      expect(harness.controller.position.isScrollingNotifier.value, isTrue);
    }
    expect(delayedCard, isNotNull, reason: 'The expensive fill must execute.');
    final laterCards = shells.difference({delayedCard});
    expect(laterCards, isNotEmpty);
    for (final index in laterCards) {
      expect(harness.stages[index], 4, reason: 'moving card $index starved');
    }
    expect(tester.takeException(), isNull);
    await finger.cancel();
  }, semanticsEnabled: false);

  testWidgets('medium drag mounts new native cards as shells', (tester) async {
    final harness = await _mount(tester);
    final before = harness.firstStages.keys.toSet();
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_viewport)),
    );
    // Win the drag gesture arena before measuring the actual scrolling move.
    await finger.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 16));
    await finger.moveBy(const Offset(0, -400));
    // Public motion input avoids wall-clock-dependent Timeline sampling in a
    // fake-clock widget test. This is below the old fast-only shell threshold.
    harness.preparation.speed = 500;
    await tester.pump(const Duration(milliseconds: 16));
    final added = harness.firstStages.keys.toSet().difference(before);
    expect(added, isNotEmpty);
    for (final index in added) {
      expect(harness.firstStages[index]!.single, 0, reason: 'new card $index');
    }
    await finger.cancel();
  }, semanticsEnabled: false);

  testWidgets('caught fling mounts shells while a stationary finger stays down', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final completed = {
      for (final index in harness.visible(tester))
        if (harness.stages[index] == 4)
          index: harness.card(index).evaluate().single,
    };
    expect(completed, isNotEmpty);
    await tester.fling(find.byKey(_viewport), const Offset(0, -240), 1200);
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controller.position.isScrollingNotifier.value, isTrue);

    // Catch the ballistic motion without beginning another drag. Flutter enters
    // HoldScrollActivity: scrolling is false, but pointer contact remains true.
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_viewport)),
    );
    // Enter the public hold activity explicitly: fake gesture-arena deadlines
    // differ from native pointer delivery, which the device workload covers.
    final hold = harness.controller.position.hold(() {});
    await tester.pump();
    expect(harness.controller.position.isScrollingNotifier.value, isFalse);
    final heldOffset = harness.controller.offset;
    final before = harness.firstStages.keys.toSet();

    // Mount extra cards through layout while preserving the held scroll offset.
    // This isolates initial-stage selection from motion and the idle fill timer.
    harness.cacheExtent.value = _extent * 4;
    await tester.pump();
    expect(harness.controller.offset, heldOffset);
    expect(harness.controller.position.isScrollingNotifier.value, isFalse);
    final added = harness.firstStages.keys.toSet().difference(before);
    expect(added, isNotEmpty);
    for (final index in added) {
      expect(
        harness.firstStages[index]!.single,
        0,
        reason: 'held new card $index',
      );
    }
    for (final entry in completed.entries) {
      expect(entry.value.mounted, isTrue);
      expect(harness.card(entry.key).evaluate().single, same(entry.value));
      expect(
        harness.stages[entry.key],
        4,
        reason: 'completed card ${entry.key}',
      );
    }
    expect(tester.takeException(), isNull);
    hold.cancel();
    await finger.cancel();
  }, semanticsEnabled: false);

  testWidgets('evicted completed cards remount as shells on reverse drag', (
    tester,
  ) async {
    final harness = await _mount(tester);
    final initial = harness.visible(tester);
    expect(initial, isNotEmpty);
    final originalElements = {
      for (final index in initial) index: harness.card(index).evaluate().single,
    };
    for (final index in initial) {
      expect(harness.stages[index], 4);
    }
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(_viewport)),
    );
    for (var step = 0; step < 16; step++) {
      await finger.moveBy(const Offset(0, -1100));
      harness.preparation.speed = 4000;
      await _frames(tester, 2);
      expect(harness.retained, lessThanOrEqualTo(32));
    }
    expect(harness.firstStages.length, greaterThan(32));
    expect(
      originalElements.values.every((element) => !element.mounted),
      isTrue,
    );
    await finger.moveBy(Offset(0, harness.controller.offset));
    harness.preparation.speed = 4000;
    await tester.pump(const Duration(milliseconds: 16));
    final returned = harness.visible(tester).intersection(initial);
    expect(returned, isNotEmpty);
    for (final index in returned) {
      expect(harness.firstStages[index], hasLength(2));
      expect(
        harness.firstStages[index]!.last,
        0,
        reason: 'disposed completion must not survive remount of $index',
      );
    }
    await finger.cancel();
  }, semanticsEnabled: false);

  testWidgets(
    'visible shells drain within 250ms while drag finger stays down',
    (tester) async {
      final harness = await _mount(tester);
      final finger = await tester.startGesture(
        tester.getCenter(find.byKey(_viewport)),
      );
      // Leave many unfinished retained children behind and expose fresh cards.
      // Their stale render coordinates must not starve the actual viewport.
      await finger.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 16));
      for (final distance in [-1100.0, -1100.0, -1100.0, -1100.0, -660.0]) {
        await finger.moveBy(Offset(0, distance));
        harness.preparation.speed = 4000;
        await tester.pump(const Duration(milliseconds: 16));
      }
      final visible = harness.visible(tester);
      expect(visible, isNotEmpty);
      expect(visible.any((index) => harness.stages[index]! < 4), isTrue);
      // No pointer-up, ScrollEndNotification, or additional motion wakes work.
      // Fifteen fake 60Hz frames are 240ms; this is a scheduling bound, not a
      // claim about native device frame time or input latency.
      harness.preparation.speed = 0;
      await _frames(tester, 15);
      for (final index in visible) {
        expect(harness.stages[index], 4, reason: 'visible card $index starved');
      }
      expect(harness.retained, lessThanOrEqualTo(32));
      expect(tester.takeException(), isNull);
      await finger.cancel();
    },
    semanticsEnabled: false,
  );
}
