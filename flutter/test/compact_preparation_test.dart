import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

ScrollableState viewportState(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const PageStorageKey('recipes-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

Future<(LocalPreferences, ScrollController, CardPreparation)> mount(
  WidgetTester tester,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  final preferences = LocalPreferences.memory()..view = RecipeView.compact;
  final store = RecipeStore(
    FakeRepository([
      for (var i = 0; i < 500; i++) recipe('$i', title: 'Garden soup $i'),
    ]),
    preferences,
  );
  final controller = ScrollController();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    store.dispose();
    preferences.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });
  await store.initialize();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RecipesScreen(
          store: store,
          preferences: preferences,
          controller: controller,
          onOpenRecipe: (_) {},
          onActions: (_) {},
          onAdd: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final work = tester
      .widget<ProgressiveCards>(find.byType(ProgressiveCards))
      .preparation;
  return (preferences, controller, work);
}

void main() {
  testWidgets('Compact keeps one viewport and does not queue Cards work', (
    tester,
  ) async {
    final (_, controller, work) = await mount(tester);
    final scrollState = viewportState(tester);
    expect(find.byType(ProgressiveCard), findsNothing);
    controller.jumpTo(1000);
    final withoutPause = tester.binding.transientCallbackCount;
    await tester.pumpAndSettle();
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    work.paused.value = true;
    controller.jumpTo(1000);
    final withPause = tester.binding.transientCallbackCount;
    expect(
      withoutPause,
      withPause,
      reason:
          'Pausing a card-free list must not remove extra preparation work.',
    );
    expect(viewportState(tester), same(scrollState));
    await tester.pumpAndSettle();
    expect(controller.offset, 1000);
  }, semanticsEnabled: false);

  testWidgets(
    'Cards return after Compact without stale work or lost viewport',
    (tester) async {
      CardShellMetrics.enabled = true;
      CardShellMetrics.reset();
      addTearDown(() {
        CardShellMetrics.enabled = false;
        CardShellMetrics.reset();
      });
      final (preferences, controller, work) = await mount(tester);
      controller.jumpTo(700);
      await tester.pumpAndSettle();
      final scrollState = viewportState(tester);
      for (var i = 0; i < 3; i++) {
        preferences.setView(RecipeView.cards);
        await tester.pumpAndSettle();
        expect(find.byType(ProgressiveCard), findsWidgets);
        expect(
          tester
              .widget<ProgressiveCards>(find.byType(ProgressiveCards))
              .enabled,
          isTrue,
        );
        expect(viewportState(tester), same(scrollState));
        controller.jumpTo(controller.offset + 120);
        // Disable with preparation scheduled, then verify the viewport survives
        // a quick return. The moving check below proves scheduling reattaches.
        preferences.setView(RecipeView.compact);
        await tester.pump();
        preferences.setView(RecipeView.cards);
        await tester.pumpAndSettle();
        expect(find.byType(ProgressiveCard), findsWidgets);
        preferences.setView(RecipeView.compact);
        await tester.pumpAndSettle();
        expect(find.byType(ProgressiveCard), findsNothing);
        expect(
          tester
              .widget<ProgressiveCards>(find.byType(ProgressiveCards))
              .enabled,
          isFalse,
        );
        expect(viewportState(tester), same(scrollState));
        expect(controller.offset, greaterThanOrEqualTo(700));
        expect(tester.takeException(), isNull);
      }
      preferences.setView(RecipeView.cards);
      await tester.pumpAndSettle();
      final shellsBefore = CardShellMetrics.snapshot()['createdShells'] as int;
      final finger = await tester.startGesture(
        tester.getCenter(find.byKey(const PageStorageKey('recipes-scroll'))),
      );
      await finger.moveBy(const Offset(0, -24));
      await tester.pump(const Duration(milliseconds: 16));
      await finger.moveBy(const Offset(0, -3000));
      // Timeline wall time is not the widget test's fake clock. Supply the same
      // public speed input used by progressive_cards_scheduling_test.
      work.speed = 500;
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        CardShellMetrics.snapshot()['createdShells'] as int,
        greaterThan(shellsBefore),
        reason: 'Returning Cards must use automatic shells during motion.',
      );
      for (var frame = 0; frame < 90; frame++) {
        final before = controller.offset;
        await finger.moveBy(const Offset(0, -1));
        work.speed = 500;
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        expect(controller.offset, greaterThan(before));
      }
      expect(
        CardShellMetrics.snapshot()['unfinishedVisible'],
        0,
        reason:
            'Re-enabled preparation must finish visible shells during motion.',
      );
      await finger.cancel();
      expect(viewportState(tester), same(scrollState));
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: false,
  );
}
