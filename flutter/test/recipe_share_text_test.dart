import 'package:cookdex/recipe_share_text.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/readable_share_recipe.dart';
import 'recipe_store_test.dart' show recipe;

void main() {
  test('message includes saved recipe content in readable cooking order', () {
    final value = readableShareRecipe();
    expect(recipeShareText(value), '''Lemon oat pancakes

Tender pancakes with a bright lemon finish.

Serves 4 · Prep 10 min · Cook 15 min · Total 25 min

Ingredients
- 1 lemon, zested

Batter
- 1½ cups oat flour
- ¾–1¼ cups milk, add as needed
- salt, to taste

To serve
- ⅓ cup berries, washed (optional)

Steps
1. Mix the batter: Stir the flour, milk, salt and lemon zest until combined.
2. Cook: Spoon into a warm pan. Turn when bubbles form; cook until golden.
3. Serve: Top with the berries.

Notes
Make the batter just before cooking.

Chill leftovers for tomorrow. Reheat gently.

Source: https://example.org/lemon-oat-pancakes''');
    expect(value.fields.servings, '4');
    expect(
      value.fields.ingredients[1].amount,
      const Amount.rational(numerator: 3, denominator: 2),
    );
  });

  test('count yields use Makes while servings and ranges use Serves', () {
    for (final (saved, expected) in [
      ('Makes 12 pancakes', 'Makes 12 pancakes'),
      ('serves 4 to 6', 'Serves 4–6'),
      ('6 servings', 'Serves 6'),
    ]) {
      final text = recipeShareText(readableShareRecipe(servings: saved));
      expect(text, contains('\n$expected · Prep'));
    }
  });

  test(
    'source attribution is plain while complete URL punctuation survives',
    () {
      for (final (source, expected) in [
        ('**Community cookbook**, page 12', 'Community cookbook, page 12'),
        (
          'https://example.org/keep__literal__?x=one&y=two',
          'https://example.org/keep__literal__?x=one&y=two',
        ),
      ]) {
        expect(
          recipeShareText(readableShareRecipe(source: source)),
          endsWith('Source: $expected'),
        );
      }
    },
  );

  test('notes keep real paragraphs and remove Markdown formatting', () {
    final value = recipe(
      'notes',
      notes:
          '## **Make ahead:**\r\nChill *overnight*.\r\n\r\n'
          '> __To serve:__ Warm `gently`. Keep a literal folder\\recipes path.\r\n'
          '[Serving tips](https://example.org/tips)',
      description: 'A **soft** crumb.',
    );
    final text = recipeShareText(value);
    expect(text, contains('A soft crumb.'));
    expect(
      text,
      contains(
        'Notes\nMake ahead:\nChill overnight.\n\n'
        'To serve: Warm gently. Keep a literal folder\\recipes path.\n'
        'Serving tips',
      ),
    );
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('__')));
    expect(text, isNot(contains(r'\n')));
  });

  test('uncommon fractions stay exact and no library metadata is emitted', () {
    final value = recipe('private-id', favorite: true, revision: 7);
    final text = recipeShareText(value);
    expect(text, contains('- 33/100 cup cream [fresh]'));
    for (final excluded in [
      'private-id',
      'Quick',
      'favorite',
      'revision',
      '2026-01',
      'Recipe Book',
      'schema',
      'photo',
    ]) {
      expect(text, isNot(contains(excluded)));
    }
  });

  test(
    'empty fields add no empty headings and source attribution is retained',
    () {
      final base = readableShareRecipe();
      final fields = RecipeFields(
        title: 'Simple rice',
        description: '',
        servings: '',
        prepTime: '',
        cookTime: '',
        totalTime: '',
        source: 'Community cookbook, page 12',
        tags: const [],
        notes: '',
        ingredients: const [],
        steps: const [],
      );
      expect(
        recipeShareText(
          Recipe(
            id: base.id,
            favorite: base.favorite,
            revision: base.revision,
            createdAt: base.createdAt,
            updatedAt: base.updatedAt,
            fields: fields,
          ),
        ),
        'Simple rice\n\nSource: Community cookbook, page 12',
      );
    },
  );
}
