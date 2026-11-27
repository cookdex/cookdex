import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/idle_build_ahead.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

Future<(RecipeStore, LocalPreferences, ScrollController)> _mount(
  WidgetTester tester,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 760);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final preferences = LocalPreferences.memory()
    ..view = RecipeView.compact
    ..sort = RecipeSort.title;
  final store = RecipeStore(
    FakeRepository([
      for (var i = 0; i < 300; i++)
        recipe('$i', title: 'Garden soup ${i.toString().padLeft(3, '0')}'),
    ]),
    preferences,
  );
  final controller = ScrollController();
  await store.initialize();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: RecipesScreen(
          store: store,
          preferences: preferences,
          controller: controller,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    BuiltRowBudget.debugRetained = null;
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    store.dispose();
    preferences.dispose();
  });
  return (store, preferences, controller);
}

Future<(Element, double)> _leaveRowBehind(
  WidgetTester tester,
  ScrollController controller,
) async {
  controller.jumpTo(1400);
  await tester.pumpAndSettle();
  final row = find.byKey(const ValueKey('30'));
  final element = row.evaluate().single;
  final oldOffset = controller.offset;
  final viewport = tester.getRect(
    find.byKey(const PageStorageKey('recipes-scroll')),
  );
  // Move this entire row above the normal 250 dp layout cache.
  controller.jumpTo(
    oldOffset + tester.getRect(row).bottom - viewport.top + 270,
  );
  await tester.pumpAndSettle();
  return (element, oldOffset);
}

void main() {
  testWidgets('Compact reuses a row on reversal and releases distant rows', (
    tester,
  ) async {
    final (_, _, controller) = await _mount(tester);
    var peakRetained = 0;
    BuiltRowBudget.debugRetained = (count) {
      if (count > peakRetained) peakRetained = count;
    };
    final (element, offset) = await _leaveRowBehind(tester, controller);
    expect(element.mounted, isTrue);
    controller.jumpTo(offset);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('30')).evaluate().single, same(element));
    for (final offset in [4000.0, 8000.0, 12000.0]) {
      controller.jumpTo(offset);
      await tester.pumpAndSettle();
    }
    expect(element.mounted, isFalse);
    expect(peakRetained, 32);
    expect(
      find.byType(KeepBuilt, skipOffstage: false).evaluate().length,
      lessThan(64),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained Compact rows update favorites and survive view changes',
    (tester) async {
      final (store, preferences, controller) = await _mount(tester);
      await _leaveRowBehind(tester, controller);
      await store.toggleFavorite('30');
      await tester.pumpAndSettle();
      preferences.setFavoritesOnly(true);
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Unfavorite Garden soup 030'),
        findsOneWidget,
      );
      expect(find.text('Garden soup 029'), findsNothing);
      preferences.setView(RecipeView.cards);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Unfavorite Garden soup 030'), findsOneWidget);
      preferences.setView(RecipeView.compact);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Unfavorite Garden soup 030'));
      await tester.pumpAndSettle();
      expect(find.text('No matching recipes'), findsOneWidget);
      expect(
        store.summaries.singleWhere((recipe) => recipe.id == '30').favorite,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
