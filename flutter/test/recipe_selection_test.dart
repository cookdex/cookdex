import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:flutter/gestures.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;

import 'package:material_symbols_icons/symbols.dart';
import 'package:cookdex/export_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/components.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

void main() {
  testWidgets(
    'integrated mouse selection and Back preserve search; detail Select returns list',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = LocalPreferences.memory()..setQuery('soup');
      final store = RecipeStore(
        FakeRepository([
          recipe('one', title: 'Garden soup'),
          recipe('two', title: 'Tomato soup'),
        ]),
        preferences,
      );
      await store.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: ShellPlatform(),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Garden soup').first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      expect(find.text('Select'), findsOneWidget);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Tomato soup').first);
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byType(RecipeDetail), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close selection'), findsNothing);
      expect(preferences.query, 'soup');
      expect(find.byType(RecipesScreen), findsOneWidget);
      expect(find.byType(RecipeDetail), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(preferences.query, isEmpty);
      await tester.tap(find.text('Garden soup').first);
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsOneWidget);
      await tester.tap(find.byTooltip('Recipe actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsNothing);
      expect(find.byType(RecipesScreen), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      final selected = tester
          .widget<RecipesScreen>(find.byType(RecipesScreen))
          .selectedIds;
      expect(selected, {'one'});
      expect(tester.takeException(), isNull);
    },
  );

  for (final android in [true, false]) {
    testWidgets('share options on Android=$android', (tester) async {
      ExportAction? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  chosen = await showShareOptions(context, isAndroid: android);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Send as message'), findsOneWidget);
      expect(find.text('Copy text'), findsOneWidget);
      expect(find.text('Save .txt file'), findsOneWidget);
      await tester.tap(find.text('Send as .txt file'));
      await tester.pumpAndSettle();
      expect(chosen, ExportAction.shareFile);
    });
  }
  testWidgets('selection toggles cached rows and disables empty actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = LocalPreferences.memory();
    final repository = FakeRepository([
      recipe('one'),
      recipe('two', title: 'Soup'),
    ]);
    final store = RecipeStore(repository, preferences);
    await store.initialize();
    addTearDown(() {
      store.dispose();
      preferences.dispose();
    });
    Set<String>? selected = {'one'};
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => RecipesScreen(
              store: store,
              preferences: preferences,
              selectedIds: selected,
              onToggleSelection: (id) => update(() {
                selected!.contains(id)
                    ? selected!.remove(id)
                    : selected!.add(id);
              }),
              onCloseSelection: () => update(() => selected = null),
              onSelectAll: () => update(() => selected = {'one', 'two'}),
              onShareSelection: () {},
              onShoppingSelection: () {},
              onOpenRecipe: (_) => opened++,
              onAdd: () {},
              onActions: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(
      tester.widgetList<Checkbox>(find.byType(Checkbox)).map((w) => w.value),
      containsAll([true, false]),
    );
    await tester.tap(find.text('Lemon cake'));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(find.text('0 selected'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Symbols.share))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close selection'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    await tester.tap(find.text('Soup'));
    expect(opened, 1);
  });
}
