import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, DuplicateEditorFake;

Recipe namedRecipe(String id, String name, {String tag = 'Dinner'}) => Recipe(
  id: id,
  favorite: false,
  revision: 1,
  createdAt: '2026-10-01T00:00:00Z',
  updatedAt: '2026-10-01T00:00:00Z',
  fields: RecipeFields(
    title: 'Synthetic recipe $id',
    description: '',
    servings: '2',
    prepTime: '',
    cookTime: '',
    totalTime: '',
    source: '',
    notes: '',
    steps: ['Mix.'],
    tags: [tag],
    ingredients: [
      Ingredient(
        amount: const Amount.unspecified(),
        unit: '',
        name: name,
        prepNote: '',
        optional: false,
        section: '',
      ),
    ],
  ),
);

Future<void> reviewHarness(WidgetTester tester, EditorController c) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => c.save(
              reviewNames: (matches) => showDialog<Set<int>>(
                context: context,
                builder: (_) => NameMatchReview(matches: matches),
              ),
            ),
            child: const Text('Save recipe'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Save recipe'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'only changed names are offered after amount edits and moving rows',
    () async {
      final base = namedRecipe('base', 'SALT.', tag: 'DINNER.');
      final (c, _, _) = await controller(
        base: base,
        recipes: [base, namedRecipe('a', 'Salt'), namedRecipe('b', 'Salt')],
      );
      final row = c.draft.sections.single.rows.removeAt(0);
      row.amount = '2';
      row.prepNote = 'finely ground';
      c.draft.sections.add(EditableSection(name: 'Sauce', rows: [row]));
      c.changed();
      expect(c.nameMatches(), isEmpty);
      row.name = 'salt';
      c.draft.tags.add('dinner');
      final matches = c.nameMatches();
      expect(matches.map((m) => m.entered), ['salt', 'dinner']);
      expect(matches.map((m) => m.preferred), ['Salt', 'Dinner']);
      expect(matches.map((m) => m.tag), [false, true]);
    },
  );

  testWidgets('checked names change; unchecked names retain entered spelling', (
    tester,
  ) async {
    final (c, repo, _) = await controller(recipes: [namedRecipe('a', 'Salt')]);
    c.draft.title = 'Synthetic new dish';
    c.draft.sections.single.rows.single.name = 'SALT.';
    c.draft.tags.add('DINNER.');
    c.changed();
    await reviewHarness(tester, c);
    expect(find.text('Match library names?'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('name-match-0')))
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const ValueKey('name-match-1')))
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('name-match-1')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    final saved = repo.recipes['new-1']!;
    expect(saved.fields.ingredients.single.name, 'Salt');
    expect(saved.fields.tags, ['DINNER.']);
  });

  testWidgets('Back leaves the draft intact and saves nothing', (tester) async {
    final (c, repo, _) = await controller(recipes: [namedRecipe('a', 'Salt')]);
    c.draft.title = 'Synthetic new dish';
    c.draft.sections.single.rows.single.name = 'SALT.';
    c.changed();
    await reviewHarness(tester, c);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(c.draft.sections.single.rows.single.name, 'SALT.');
    expect(c.dirty, isTrue);
    expect(c.saving, isFalse);
    expect(c.draft.error, isNull);
  });

  test(
    'declined spelling is not offered again after reopening saved recipe',
    () async {
      final library = [namedRecipe('a', 'Salt'), namedRecipe('b', 'Salt')];
      final (c, _, store) = await controller(recipes: library);
      c.draft.title = 'Synthetic deliberate spelling';
      c.draft.sections.single.rows.single.name = 'SALT.';
      c.draft.tags.add('DINNER.');
      c.changed();
      final saved = await c.save(reviewNames: (_) async => <int>{});
      expect(saved, isNotNull);
      final reopened = await EditorController.create(
        store: store,
        storage: MemoryDraftStorage(),
        base: saved,
      );
      addTearDown(reopened.dispose);
      reopened.draft.description = 'An unrelated edit';
      reopened.changed();
      expect(reopened.nameMatches(), isEmpty);
      expect(reopened.draft.tags, ['DINNER.']);
    },
  );

  test(
    'imported candidates use the same review before import is saved',
    () async {
      final repo = DuplicateEditorFake([namedRecipe('a', 'Salt')]);
      final store = RecipeStore(repo, LocalPreferences.memory());
      await store.initialize();
      final c = await EditorController.create(
        store: store,
        storage: MemoryDraftStorage(),
        imported: Candidate(
          recipe: namedRecipe('imported', 'SALT.', tag: 'DINNER.'),
          warnings: const [],
          ingredientSources: const [],
        ),
      );
      addTearDown(() {
        c.dispose();
        store.dispose();
      });
      var reviews = 0;
      final saved = await c.save(
        reviewNames: (matches) async {
          reviews++;
          expect(repo.saves, 0);
          expect(matches.map((m) => m.entered), ['SALT.', 'DINNER.']);
          return {0, 1};
        },
      );
      expect(reviews, 1);
      expect(repo.saves, 1);
      expect(saved!.fields.ingredients.single.name, 'Salt');
      expect(saved.fields.tags, ['Dinner']);
    },
  );

  test('whitespace is cleaned without suggesting a spelling change', () async {
    final (c, _, _) = await controller(recipes: [namedRecipe('a', 'Sea salt')]);
    c.draft.title = 'Synthetic whitespace';
    c.draft.sections.single.rows.single.name = '  Sea\t salt  ';
    c.draft.tags.add('  Dinner  ');
    c.changed();
    expect(c.nameMatches(), isEmpty);
    final saved = await c.save();
    expect(saved!.fields.ingredients.single.name, 'Sea salt');
    expect(saved.fields.tags, ['Dinner']);
  });
}
