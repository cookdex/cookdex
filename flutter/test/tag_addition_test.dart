import 'package:cookdex/editor_model.dart';
import 'package:cookdex/library_catalog.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'selection_actions.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'library_screen_test.dart' show LibraryFakeRepository;
import 'recipe_store_test.dart' show recipe;

List<Recipe> tagFixtures([int count = 60]) => [
  for (var i = 0; i < count; i++)
    recipeFromJson(() {
      final json = recipeToJson(
        recipe(
          'tag-$i',
          title: 'Garden recipe ${i.toString().padLeft(3, '0')}',
        ),
      );
      json['favorite'] = i.isEven;
      (json['fields'] as Map<String, dynamic>)['tags'] = [
        i % 3 == 0 ? 'quick' : 'slow',
        if (i < 2) 'weeknight',
      ];
      return json;
    }()),
];

void main() {
  test('Tag matching uses duplicate keys but does not equate punctuation-only names', () {
    final repo = LibraryFakeRepository(tagFixtures(1));
    final catalog = LibraryCatalog(repo.current.summaries, LibraryKind.tags);
    expect(catalog.matchingTag('WEEKNIGHT!')!.name, 'weeknight');
    catalog.names.add(LibraryName('!', []));
    expect(catalog.matchingTag('!')!.name, '!');
    expect(catalog.matchingTag('...'), isNull);
  });

  test('Picker uses the exact recipe-list ordering and search fields at 500 recipes', () async {
    final prefs = LocalPreferences.memory();
    final store = RecipeStore(LibraryFakeRepository(tagFixtures(500)), prefs);
    await store.initialize();
    for (final sort in RecipeSort.values) {
      for (final favorites in [false, true]) {
        for (final fields in [
          LocalPreferences.defaultSearchFields,
          {SearchField.tags},
          {SearchField.title},
        ]) {
          prefs.setSort(sort);
          prefs.setFavoritesOnly(favorites);
          prefs.setSearchFields(fields);
          prefs.setQuery('quick');
          expect(
            store.recipesMatching(prefs).map((r) => r.id),
            store.visibleRecipes.map((r) => r.id),
          );
        }
      }
    }
    prefs.resetSearch();
    expect(store.recipesMatching(prefs), hasLength(500));
    store.dispose();
    prefs.dispose();
  });

  testWidgets(
    'New tag cancels safely, selects offscreen matches and undoes the full batch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = LocalPreferences.memory()..sort = RecipeSort.title;
      final repo = LibraryFakeRepository(tagFixtures());
      final store = RecipeStore(repo, prefs);
      await store.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: LibraryScreen(store: store, onOpenRecipe: (_, _) {}),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String s) async {
        await tester.tap(find.text(s).first);
        await tester.pumpAndSettle();
      }

      await tap('Tags');
      await tap('New tag');
      await tap('Cancel');
      expect(repo.changes, 0);
      await tap('New tag');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).autofocus,
        isFalse,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.enterText(find.byType(TextField).last, 'picnic');
      await tester.pumpAndSettle();
      await tap('Choose recipes');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.changes, 0);
      expect(
        LibraryCatalog(store.summaries, LibraryKind.tags).named('picnic'),
        isNull,
      );
      await tap('New tag');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).autofocus,
        isFalse,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.enterText(find.byType(TextField).last, 'picnic');
      await tester.pumpAndSettle();
      await tap('Choose recipes');
      await tester.enterText(find.byType(TextField).last, 'quikc');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tap('Favorites');
      await tap('Select all (10)');
      expect(find.text('10 selected'), findsOneWidget);
      await tap('Add');
      expect(find.text('Add “picnic” to 10 recipes?'), findsOneWidget);
      await tap('Cancel');
      expect(repo.changes, 0);
      await tap('Add');
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      expect(repo.changes, 1);
      expect(
        store.summaries
            .where((r) => r.tags.contains('picnic'))
            .map((r) => r.id)
            .toSet(),
        {for (var i = 0; i < 60; i += 6) 'tag-$i'},
      );
      expect(prefs.query, isEmpty);
      expect(prefs.favoritesOnly, isFalse);
      await tap('Undo');
      expect(
        LibraryCatalog(store.summaries, LibraryKind.tags).named('picnic'),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Matching tag spelling and checked locked recipes only add to new recipes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = LocalPreferences.memory()..sort = RecipeSort.title;
      final repo = LibraryFakeRepository(tagFixtures());
      final store = RecipeStore(repo, prefs);
      await store.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: LibraryScreen(store: store, onOpenRecipe: (_, _) {}),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String s) async {
        await tester.tap(find.text(s).first);
        await tester.pumpAndSettle();
      }

      await tap('Tags');
      await tap('New tag');
      expect(
        tester.widget<TextField>(find.byType(TextField).last).autofocus,
        isFalse,
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.enterText(find.byType(TextField).last, 'WEEKNIGHT!');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This matches “weeknight” (2 recipes), so that spelling will be used.',
        ),
        findsOneWidget,
      );
      await tap('Choose recipes');
      for (final id in ['tag-0', 'tag-1']) {
        final row = tester.widget<CheckboxListTile>(
          find.byKey(ValueKey(('tag-recipe', id))),
        );
        expect(row.value, isTrue);
        expect(row.onChanged, isNull);
      }
      await tester.enterText(find.byType(TextField).last, 'quikc');
      await tester.pumpAndSettle();
      expect(find.text('Select all (19)'), findsOneWidget);
      expect(
        find.text('1 already tagged · checked and locked'),
        findsOneWidget,
      );
      await tap('Favorites');
      expect(find.text('Select all (9)'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'no matches');
      await tester.pumpAndSettle();
      expect(find.textContaining('already tagged ·'), findsNothing);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      tester.testTextInput.hide();
      await tester.tap(find.byTooltip('Clear search').last);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.text('Select all (29)'), findsOneWidget);
      await tap('Favorites');
      await tap('Select all (58)');
      expect(find.text('58 selected'), findsOneWidget);
      await tap('Add');
      expect(find.text('Add “weeknight” to 58 recipes?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      expect(
        store.summaries.every(
          (r) => r.tags.where((t) => t == 'weeknight').length == 1,
        ),
        isTrue,
      );
      expect(repo.recipes['tag-0']!.revision, 1);
      await tap('Undo');
      expect(
        store.summaries.where((r) => r.tags.contains('weeknight')),
        hasLength(2),
      );
      await tap('weeknight');
      await tap('Add to recipes…');
      expect(
        find.text('2 already tagged · checked and locked'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(repo.changes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Recipes Select all includes every field-and-Favorites match and Add tag uses exactly that set',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final prefs = LocalPreferences.memory()
        ..query = 'quick'
        ..searchFields = {SearchField.tags}
        ..favoritesOnly = true
        ..sort = RecipeSort.title;
      final repo = LibraryFakeRepository(tagFixtures());
      final store = RecipeStore(repo, prefs);
      await store.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: ShellPlatform(),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(prefs.favoritesOnly, isTrue);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(prefs.query, isEmpty);
      expect(prefs.favoritesOnly, isTrue);
      expect(prefs.searchFields, {SearchField.tags});
      expect(tester.testTextInput.isVisible, isFalse);
      prefs.setQuery('quick');
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Garden recipe 000').first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tapSelectionAction(tester, 'Select all', 'Select all');
      await tester.pumpAndSettle();
      expect(
        tester.widget<RecipesScreen>(find.byType(RecipesScreen)).selectedIds,
        {for (var i = 0; i < 60; i += 6) 'tag-$i'},
      );
      await tapSelectionAction(tester, 'Add tag', 'Add tag');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.changes, 0);
      await tapSelectionAction(tester, 'Add tag', 'Add tag');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Summer!');
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Add “Summer!” to 10 recipes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.changes, 0);
      await tapSelectionAction(tester, 'Add tag', 'Add tag');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Summer!');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Add'));
      await tester.pumpAndSettle();
      expect(
        store.summaries
            .where((r) => r.tags.contains('Summer!'))
            .map((r) => r.id)
            .toSet(),
        {for (var i = 0; i < 60; i += 6) 'tag-$i'},
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      prefs.resetSearch();
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Garden recipe 000').first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tapSelectionAction(tester, 'Select all', 'Select all');
      await tester.pumpAndSettle();
      expect(
        tester.widget<RecipesScreen>(find.byType(RecipesScreen)).selectedIds,
        hasLength(60),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
