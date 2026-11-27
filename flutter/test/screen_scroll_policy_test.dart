import 'dart:io';

import 'package:cookdex/help_content.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'recipe_store_test.dart' show recipe;
import 'shopping_screen_test.dart' show ShoppingFake, item;

Future<LocalPreferences> _mount(WidgetTester tester, {int recipes = 64}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 760);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final prefs = LocalPreferences.memory()
    ..sort = RecipeSort.title
    ..view = RecipeView.compact;
  final repository = ShoppingFake(
    [
      for (var i = 0; i < recipes; i++)
        recipe(
          '$i',
          title: 'Garden soup ${i.toString().padLeft(2, '0')}',
          notes: List.filled(
            60,
            'Stir gently until the vegetables soften.',
          ).join('\n'),
        ),
    ],
    [for (var i = 0; i < 80; i++) item('$i', 'Pantry item $i')],
  );
  final store = RecipeStore(repository, prefs);
  await store.initialize();
  await tester.pumpWidget(
    CookdexApp(
      store: store,
      platform: ShellPlatform(),
      importService: ImportFakeService(),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
  });
  return prefs;
}

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

ScrollPosition _keyedPosition(WidgetTester tester, String key) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(PageStorageKey(key)),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

void main() {
  testWidgets('empty library opens Getting started in the guide', (
    tester,
  ) async {
    await _mount(tester, recipes: 0);
    final guide = find.text(helpTitle);
    await tester.ensureVisible(guide);
    await tester.tap(guide);
    await tester.pumpAndSettle();
    expect(find.text(helpIntroduction).hitTestable(), findsOneWidget);
    expect(
      find.text(helpSections.first.paragraphs.first).hitTestable(),
      findsOneWidget,
    );
    expect(find.text(dataHelp.paragraphs.first), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('No recipes caught yet'), findsOneWidget);
  });

  testWidgets(
    'new recipe searches start at top and Clear restores the full list',
    (tester) async {
      final prefs = await _mount(tester);
      final scroll = tester
          .widget<RecipesScreen>(find.byType(RecipesScreen))
          .controller!;
      scroll.jumpTo(880);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('recipe-search')), 'garden');
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      scroll.jumpTo(360);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('recipe-search')), 'soup');
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      await tester.enterText(
        find.byKey(const Key('recipe-search')),
        'xyzxyzxyz',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching recipes'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(prefs.query, isEmpty);
      expect(scroll.offset, 880);
    },
  );

  testWidgets('three tab reselections and switching between retained lists', (
    tester,
  ) async {
    await _mount(tester);
    final recipes = tester
        .widget<RecipesScreen>(find.byType(RecipesScreen))
        .controller!;
    recipes.jumpTo(860);
    await tester.pumpAndSettle();
    await _tab(tester, 'Shopping list');
    final shopping = tester
        .widget<ShoppingScreen>(find.byType(ShoppingScreen))
        .controller!;
    shopping.jumpTo(620);
    await tester.pumpAndSettle();
    await _tab(tester, 'Recipes');
    expect(recipes.offset, 860);
    await _tab(tester, 'Shopping list');
    expect(shopping.offset, 620);
    await _tab(tester, 'Shopping list');
    expect(shopping.offset, 0);
    await _tab(tester, 'Settings');
    final settings = tester
        .widget<SettingsScreen>(find.byType(SettingsScreen))
        .controller!;
    settings.jumpTo(400);
    await tester.pumpAndSettle();
    await _tab(tester, 'Recipes');
    expect(recipes.offset, 860);
    await _tab(tester, 'Settings');
    expect(settings.offset, 0);
    settings.jumpTo(380);
    await tester.pumpAndSettle();
    await _tab(tester, 'Settings');
    expect(settings.offset, 0);
    await _tab(tester, 'Recipes');
    await _tab(tester, 'Recipes');
    expect(recipes.offset, 0);
  });

  testWidgets(
    'Back and the first Recipes tap restore the list, the next tap goes to top',
    (tester) async {
      await _mount(tester);
      final list = tester
          .widget<RecipesScreen>(find.byType(RecipesScreen))
          .controller!;
      await tester.enterText(find.byKey(const Key('recipe-search')), 'garden');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      list.jumpTo(720);
      await tester.pumpAndSettle();
      final visibleRecipe = find
          .textContaining('Garden soup')
          .hitTestable()
          .last;
      for (final cook in [false, true]) {
        await tester.tap(visibleRecipe);
        await tester.pumpAndSettle();
        final id = tester
            .widget<RecipeDetail>(find.byType(RecipeDetail))
            .recipeId;
        final reading = _keyedPosition(tester, 'recipe-$id');
        if (cook) {
          expect(reading.pixels, 480);
        } else {
          reading.jumpTo(480);
          await tester.pumpAndSettle();
        }
        if (cook) {
          await tester.tap(find.byKey(const Key('cook-toggle')));
          await tester.pumpAndSettle();
          reading.jumpTo(800);
          await tester.pumpAndSettle();
          expect(reading.pixels, 800);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(list.offset, 720);
      }
      await tester.tap(visibleRecipe);
      await tester.pumpAndSettle();
      final id = tester
          .widget<RecipeDetail>(find.byType(RecipeDetail))
          .recipeId;
      expect(_keyedPosition(tester, 'recipe-$id').pixels, 480);
      await _tab(tester, 'Recipes');
      expect(find.byType(RecipeDetail), findsNothing);
      expect(list.offset, 720);
      await _tab(tester, 'Recipes');
      expect(list.offset, 0);
    },
  );

  testWidgets(
    'help starts at top each time and Back keeps the Settings offset',
    (tester) async {
      await _mount(tester);
      await _tab(tester, 'Settings');
      final settings = tester
          .widget<SettingsScreen>(find.byType(SettingsScreen))
          .controller!;
      await tester.scrollUntilVisible(
        find.text(helpTitle),
        260,
        scrollable: find
            .descendant(
              of: find.byKey(const PageStorageKey('settings')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      final before = settings.offset;
      expect(before, greaterThan(0));
      for (var visit = 0; visit < 2; visit++) {
        await tester.tap(find.text(helpTitle));
        await tester.pumpAndSettle();
        final help = _keyedPosition(tester, 'how-cookdex-works');
        expect(help.pixels, 0);
        expect(
          find.text(helpSections.first.paragraphs.first).hitTestable(),
          findsOneWidget,
        );
        expect(find.text(dataHelp.paragraphs.first), findsNothing);
        help.jumpTo(300);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(settings.offset, before);
      }
    },
  );

  testWidgets(
    'reopening refreshes recency and a third recipe evicts the oldest',
    (tester) async {
      await _mount(tester);
      Future<void> visit(int id, double expected, [double? destination]) async {
        await tester.tap(
          find.text('Garden soup ${id.toString().padLeft(2, '0')}').first,
        );
        await tester.pumpAndSettle();
        final detail = _keyedPosition(tester, 'recipe-$id');
        expect(detail.pixels, expected);
        if (destination != null) {
          detail.jumpTo(destination);
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Back to recipes'));
        await tester.pumpAndSettle();
      }

      await visit(0, 0, 320);
      await visit(1, 0, 480);
      await visit(0, 320);
      await visit(2, 0, 600);
      await visit(0, 320);
      await visit(1, 0);
    },
  );

  test(
    'reading panes and the pre-search place survive a preferences reload',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cookdex-reading-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/local.json';
      final first = await LocalPreferences.load(path);
      first.setScrollOffset(464);
      first.setQuery('soup');
      first.setScrollOffset(72);
      first.openRecipeReadingOffsets('a');
      first.saveRecipeReadingOffsets('a', {
        'recipe': 300,
        'overview': 48,
        'directions': 170,
      });
      first.openRecipeReadingOffsets('b');
      first.saveRecipeReadingOffsets('b', {'recipe': 240});
      await first.flush();
      final reopened = await LocalPreferences.load(path);
      expect(reopened.scrollOffset, 72);
      reopened.setQuery('');
      expect(reopened.scrollOffset, 464);
      expect(reopened.openRecipeReadingOffsets('a'), {
        'recipe': 300,
        'overview': 48,
        'directions': 170,
      });
      reopened.openRecipeReadingOffsets('c');
      expect(reopened.openRecipeReadingOffsets('b'), isEmpty);
      first.dispose();
      await first.flush();
      reopened.dispose();
      await reopened.flush();
    },
  );
}
