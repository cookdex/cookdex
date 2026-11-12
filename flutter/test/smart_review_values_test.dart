import 'dart:typed_data';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/smart_review_values.dart';
import 'package:cookdex/src/rust/api.dart' as core;
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show EditorFake;
import 'recipe_store_test.dart' show recipe, summary;

core.Recipe _dish(
  String id,
  List<String> tags, {
  String title = 'Carrot soup',
  List<String> foods = const ['carrots', 'ginger'],
}) {
  final dish = recipe(id, title: title);
  dish.fields.tags
    ..clear()
    ..addAll(tags);
  dish.fields.ingredients
    ..clear()
    ..addAll(
      foods.map(
        (name) => core.Ingredient(
          amount: const core.Amount.rational(numerator: 33, denominator: 100),
          unit: 'cup',
          name: name,
          prepNote: '',
          section: '',
          optional: false,
        ),
      ),
    );
  return dish;
}

class _ReviewRepository extends EditorFake {
  _ReviewRepository(super.recipes);
  @override
  Future<List<String>> ingredientAmounts(
    List<core.Ingredient> ingredients,
  ) async => [for (final _ in ingredients) '0.33'];
}

void main() {
  test('YouTube review retains meal spelling and never pads sparse tags with ingredient names', () {
    final dish = _dish(
      'video',
      ['lunch'],
      title: 'Garden toast',
      foods: ['beef', 'radish'],
    );
    expect(reviewTags(dish.fields, const [], youtube: true), ['Lunch']);
    expect(
      reviewTags(dish.fields, [
        summary(_dish('existing', ['LUNCH'])),
      ], youtube: true),
      ['LUNCH'],
    );
  });
  test('reuse the preferred Library spelling before styling or adding generated tags', () {
    final existing = [
      summary(_dish('1', ['Sheet-Pan', 'QUICK BITES'])),
      summary(_dish('2', ['Sheet-Pan', 'WEEKDAY MEALS'])),
      summary(_dish('3', ['sheet pan', 'ROOT VEGETABLES'])),
    ];
    final candidate = _dish('new', ['sheet  PAN', 'chilled soup', 'Sheet-Pan']);
    expect(reviewTags(candidate.fields, existing), [
      'Sheet-Pan',
      'CHILLED SOUP',
    ]);
    expect(candidate.fields.tags, ['sheet  PAN', 'chilled soup', 'Sheet-Pan']);
  });

  for (final (libraryTags, expected) in [
    (['weeknight meals', 'sheet pan', 'Holiday Baking'], 'chilled soup'),
    (['Weeknight Meals', 'Sheet Pan', 'holiday baking'], 'Chilled Soup'),
    (['Weeknight meals', 'Sheet pan', 'HOLIDAY BAKING'], 'Chilled soup'),
    (['WEEKNIGHT MEALS', 'SHEET PAN', 'Holiday Baking'], 'CHILLED SOUP'),
  ]) {
    test(
      'new tags follow the prevailing spelling style in ${libraryTags.first}',
      () {
        final existing = [summary(_dish('library', libraryTags))];
        final ordered = reviewTags(
          _dish('new', ['ChIlLeD sOuP', 'lunch']).fields,
          existing,
        );
        expect(ordered.first, expected);
        expect(ordered, hasLength(2));
      },
    );
  }

  test(
    'skip effort ratings, keep food labels, and stop at four distinct tags',
    () {
      final dish = _dish('new', [
        'Easy',
        'low-effort',
        'Involved',
        'Beginner friendly',
        'Hard-boiled eggs',
        'Lunch',
        'lunch',
        'Picnic',
        'Packed meals',
        'Weekend',
      ]);
      expect(reviewTags(dish.fields, const []), [
        'hard-boiled eggs',
        'lunch',
        'picnic',
        'packed meals',
      ]);
    },
  );

  test('sparse suggestions use the dish and substantive ingredients to reach two useful tags', () {
    final dish = _dish(
      'new',
      ['easy'],
      title: 'Carrot soup',
      foods: ['water', 'salt', 'carrots', 'oil'],
    );
    final tags = reviewTags(dish.fields, const []);
    expect(tags, hasLength(2));
    expect(tags, contains('carrots'));
    expect(
      tags,
      isNot(anyOf(contains('salt'), contains('water'), contains('oil'))),
    );
    expect(tags.toSet(), hasLength(tags.length));
  });

  test('review quantities convert familiar whole and fractional decimals and both range endpoints', () {
    const pairs = {
      '.5': '1/2',
      '0.125': '1/8',
      '0.250': '1/4',
      '0.33': '1/3',
      '0.375': '3/8',
      '0.625': '5/8',
      '0.667': '2/3',
      '0.875': '7/8',
      '2.75': '2 3/4',
      '1.33–2.5': '1 1/3–2 1/2',
      '1 1/3': '1 1/3',
      '33/100': '33/100',
      '2.41': '2.41',
      'to taste': 'to taste',
      '': '',
    };
    for (final entry in pairs.entries) {
      expect(reviewAmount(entry.key), entry.value, reason: entry.key);
    }
  });

  for (final mode in [
    'smart create',
    'AI import',
    'exact text',
    'source metadata',
  ]) {
    test(
      'shared editor entry applies the requested review policy for $mode',
      () async {
        final exact = mode == 'exact text';
        final preserve = exact || mode == 'source metadata';
        final db = _ReviewRepository([
          _dish('existing', ['Sheet Pan', 'Lunch Ideas']),
        ]);
        final preferences = LocalPreferences.memory();
        final store = RecipeStore(db, preferences);
        addTearDown(() {
          store.dispose();
          preferences.dispose();
        });
        await store.initialize();
        final original = _dish(
          'new',
          ['easy', 'sheet pan', 'winter meals'],
          foods: ['carrots'],
        );
        final candidate = core.Candidate(
          recipe: original,
          warnings: const [],
          ingredientSources: const [],
          aiReview: mode == 'AI import'
              ? core.AiReview(
                  guessedFields: const [],
                  guessedSteps: Uint32List(0),
                )
              : null,
        );
        final storage = MemoryDraftStorage();
        final editor = await EditorController.create(
          store: store,
          storage: storage,
          imported: candidate,
          smartCreated: mode == 'smart create',
          exactTextImport: exact,
        );
        addTearDown(editor.dispose);
        expect(
          editor.draft.tags,
          preserve
              ? ['easy', 'Sheet Pan', 'winter meals']
              : ['Sheet Pan', 'Winter Meals'],
        );
        final row = editor.draft.sections.single.rows.single;
        expect(row.amount, preserve ? '0.33' : '1/3');
        expect(editor.draft.amountInputs(), preserve ? [null] : ['1/3']);
        expect(original.fields.tags, ['easy', 'sheet pan', 'winter meals']);
        await editor.flush();
        final recovered = await EditorController.create(
          store: store,
          storage: storage,
          recovered: await storage.read(),
        );
        addTearDown(recovered.dispose);
        expect(recovered.draft.tags, editor.draft.tags);
        expect(recovered.draft.amountInputs(), editor.draft.amountInputs());
      },
    );
  }
}
