import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/library_recipe_page.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'recipe_scaling_test.dart' show ScalingFake;

void main() {
  testWidgets(
    'Library recipe shopping uses its scale and Select exits to Recipes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final repo = ScalingFake();
      final prefs = LocalPreferences.memory();
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
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> scale(int value) async {
        await tap(find.byKey(const Key('recipe-scale-toggle')));
        await tap(find.byKey(Key('recipe-scale-$value')));
      }

      await tap(find.text("Mom's Taco Meat").first);
      await scale(6); // Retained shell is 3×; Library must not use this state.
      await tap(find.text('Settings').last);
      await tap(find.text('Library'));
      await tap(
        find.byKey(const ValueKey(('library-name', false, 'cream [fresh]'))),
      );
      await tap(find.text("Mom's Taco Meat"));
      expect(find.byType(LibraryRecipePage), findsOneWidget);
      await scale(4);
      for (final menu in [false, true]) {
        if (menu) {
          await tap(find.byTooltip('Recipe actions'));
        }
        await tap(find.text('Add to shopping list').last);
        expect(
          find.widgetWithText(AlertDialog, 'Add to shopping list'),
          findsOneWidget,
        );
        await tap(find.text('Add'));
        expect(repo.addedScale, 4);
        repo.addedScale = null;
      }
      await tap(find.byTooltip('Recipe actions'));
      await tap(find.text('Select'));
      expect(find.byType(LibraryRecipePage), findsNothing);
      expect(find.byType(LibraryScreen), findsNothing);
      expect(
        tester.widget<RecipesScreen>(find.byType(RecipesScreen)).selectedIds,
        {'scale'},
      );
      expect(find.text('1 selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
