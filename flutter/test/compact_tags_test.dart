import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/tag_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/polish_fixtures.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all compact tags stay on one line at $width/$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final prefs = LocalPreferences.memory()..setView(RecipeView.compact);
        final repo = PolishRepository();
        final store = RecipeStore(repo, prefs);
        await store.initialize();
        await tester.pumpWidget(
          MaterialApp(
            theme: cookdexTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: RecipesScreen(
                store: store,
                preferences: prefs,
                onOpenRecipe: (_) {},
                onAdd: () {},
                onActions: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tags = normalizeTags(repo.recipes['0']!.fields.tags).join(' · ');
        final text = tester.widget<Text>(find.text(tags).first);
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(tags.split(' · ').length, greaterThan(2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
    }
  }
}
