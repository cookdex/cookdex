import 'package:cookdex/editor_model.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

Recipe searchRecipe(
  String id,
  String title, {
  List<String> ingredients = const [],
  List<String> tags = const [],
  String description = '',
  String notes = '',
  bool favorite = false,
  int revision = 1,
}) {
  final json = recipeToJson(
    recipe(
      id,
      title: title,
      favorite: favorite,
      description: description,
      notes: notes,
      revision: revision,
    ),
  );
  final fields = json['fields'] as Map<String, dynamic>;
  fields['tags'] = tags;
  fields['ingredients'] = [
    for (final name in ingredients)
      {
        'amount': {'kind': 'unspecified'},
        'unit': '',
        'name': name,
        'prepNote': '',
        'optional': false,
        'section': '',
      },
  ];
  return recipeFromJson(json);
}

List<Recipe> searchScreenshotsRecipes() => [
  searchRecipe(
    'a',
    'Chicken and rice',
    favorite: true,
    ingredients: ['chicken', 'rice'],
    tags: ['Weeknight'],
    description: 'A simple one-pan supper.',
  ),
  searchRecipe(
    'b',
    'Lemon chicken',
    favorite: true,
    ingredients: ['chicken', 'lemon', 'fresh herbs'],
    tags: ['Quick'],
    description: 'Bright lemon and fresh herbs.',
  ),
  searchRecipe(
    'c',
    'Vegetable rice',
    favorite: true,
    ingredients: ['rice', 'peas'],
    tags: ['Vegetarian'],
    description: 'Colorful vegetables with fluffy rice.',
  ),
  searchRecipe('d', 'Tomato soup', ingredients: ['tomato'], tags: ['Lunch']),
];

void main() {
  late LocalPreferences prefs;
  late RecipeStore store;
  late FakeRepository repository;
  Future<void> setup(List<Recipe> recipes) async {
    prefs = LocalPreferences.memory();
    repository = FakeRepository(recipes);
    store = RecipeStore(repository, prefs);
    await store.initialize();
    addTearDown(() {
      store.dispose();
      prefs.dispose();
    });
  }

  List<String> ids() => store.visibleRecipes.map((r) => r.id).toList();

  test('all terms beat partial; more distinct terms beat fewer', () async {
    await setup([
      searchRecipe('a', 'Chicken'),
      searchRecipe('b', 'Chicken rice'),
      searchRecipe('c', 'Dinner', notes: 'chicken rice lemon'),
      searchRecipe('d', 'Soup'),
    ]);
    prefs.setSearchFields(SearchField.values.toSet());
    prefs.setQuery('chicken rice lemon');
    expect(ids(), ['c', 'b', 'a']);
    expect(store.partialMatchStart, 1);
  });
  test(
    'field weights prefer name, then tags/ingredients, then description/notes',
    () async {
      await setup([
        searchRecipe('a', 'A', notes: 'rice'),
        searchRecipe('b', 'B', description: 'rice'),
        searchRecipe('c', 'C', ingredients: ['rice']),
        searchRecipe('d', 'D', tags: ['rice']),
        searchRecipe('e', 'Rice'),
      ]);
      prefs.setSearchFields(SearchField.values.toSet());
      prefs.setQuery('rice');
      expect(ids(), ['e', 'c', 'd', 'a', 'b']);
      expect(store.partialMatchStart, isNull);
    },
  );
  test(
    'each term uses its best field once, not frequency or repeated fields',
    () async {
      await setup([
        searchRecipe(
          'a',
          'Dinner',
          tags: ['rice'],
          ingredients: ['rice', 'rice'],
          description: 'rice rice',
          notes: 'rice rice',
        ),
        searchRecipe('b', 'Rice'),
      ]);
      prefs.setSearchFields(SearchField.values.toSet());
      prefs.setQuery('rice');
      expect(ids(), ['b', 'a']);
    },
  );
  test('equal ranks fall back to existing selected sort and ID', () async {
    await setup([
      searchRecipe('b', 'Rice bake'),
      searchRecipe('c', 'Rice curry', revision: 2),
      searchRecipe('a', 'Rice soup'),
    ]);
    prefs.setQuery('rice');
    expect(ids(), ['c', 'a', 'b']);
    prefs.setSort(RecipeSort.title);
    expect(ids(), ['b', 'c', 'a']);
    prefs.setSort(RecipeSort.added);
    expect(ids(), ['a', 'b', 'c']);
  });
  test('prefix, inner substring and punctuation stay literal and accents add matches', () async {
    await setup([
      searchRecipe('a', 'Beef café [fresh]'),
      searchRecipe('b', 'Beet cafe'),
    ]);
    prefs.setQuery('BEE');
    expect(ids(), ['a', 'b']);
    prefs.setQuery('eef');
    expect(ids(), ['a']);
    prefs.setQuery('cafe');
    expect(ids(), ['b', 'a']);
    prefs.setQuery('CAFÉ');
    expect(ids(), ['a', 'b']);
    prefs.setQuery('[fresh]');
    expect(ids(), ['a']);
    prefs.setQuery('"beef"');
    expect(ids(), isEmpty);
  });
  test(
    'only selected targets contribute inclusion, rank and full boundary',
    () async {
      await setup([
        searchRecipe('a', 'Chicken rice', notes: 'rice'),
        searchRecipe('b', 'Rice', notes: 'chicken rice'),
        searchRecipe('c', 'Chicken'),
      ]);
      prefs.setSearchFields({SearchField.notes});
      prefs.setQuery('chicken rice');
      expect(ids(), ['b', 'a']);
      expect(store.partialMatchStart, 1);
      prefs.setSearchFields({});
      expect(ids(), isEmpty);
    },
  );
  test(
    'duplicate terms are ignored after lowercasing and whitespace splitting',
    () async {
      await setup([
        searchRecipe('a', 'Rice'),
        searchRecipe('b', 'Chicken'),
        searchRecipe('c', 'Chicken rice'),
      ]);
      prefs.setQuery('chicken rice');
      final expected = ids();
      prefs.setQuery(' CHICKEN\tchicken\n rice chicken ');
      expect(ids(), expected);
      expect(store.partialMatchStart, 1);
    },
  );
  test('filler words ignored only alongside meaningful terms', () async {
    await setup([
      searchRecipe('a', 'Chicken rice'),
      searchRecipe('b', 'Rice'),
      searchRecipe('c', 'Soup', notes: 'and or with the of a an in for to'),
    ]);
    prefs.setSearchFields(SearchField.values.toSet());
    prefs.setQuery('chicken and or with the of a an in for to rice');
    expect(ids(), ['a', 'b']);
    expect(store.partialMatchStart, 1);
  });
  test(
    'filler-only queries retain every-word inclusion and unweighted order',
    () async {
      await setup([
        searchRecipe('a', 'Dinner', notes: 'and with'),
        searchRecipe('b', 'And with'),
        searchRecipe('c', 'And'),
      ]);
      prefs.setSearchFields(SearchField.values.toSet());
      prefs.setQuery('and with');
      expect(ids(), ['a', 'b']);
      expect(store.partialMatchStart, isNull);
    },
  );
  test('empty queries and favorites preserve existing behavior', () async {
    await setup([
      searchRecipe('a', 'Rice', favorite: true),
      searchRecipe('b', 'Rice soup', revision: 2),
    ]);
    prefs.setQuery(' \n\t ');
    prefs.setSearchFields({});
    expect(ids(), ['b', 'a']);
    expect(store.partialMatchStart, isNull);
    prefs.setFavoritesOnly(true);
    expect(ids(), ['a']);
    prefs.setSearchFields({SearchField.title});
    prefs.setQuery('rice soup');
    expect(ids(), ['a']);
    expect(store.partialMatchStart, 0);
  });
  test(
    'adding a term widens inclusion and places the partial-only label first',
    () async {
      await setup([searchRecipe('a', 'Chicken'), searchRecipe('b', 'Rice')]);
      prefs.setQuery('chicken');
      expect(ids(), ['a']);
      expect(store.partialMatchStart, isNull);
      prefs.setQuery('chicken rice');
      expect(ids(), ['a', 'b']);
      expect(store.partialMatchStart, 0);
      prefs.setQuery('rice');
      expect(ids(), ['b']);
    },
  );
  test(
    'picker requires filler words and uses selected sort among literals',
    () async {
      await setup([
        searchRecipe('a', 'Supper', notes: 'chicken'),
        searchRecipe('b', 'Chicken'),
        searchRecipe('c', 'Chicken and rice'),
      ]);
      prefs.setSearchFields(SearchField.values.toSet());
      prefs.setQuery('chicken');
      expect(ids(), ['b', 'c', 'a']);
      expect(store.recipesMatching(prefs).map((r) => r.id), ['a', 'b', 'c']);
      prefs.setQuery('chicken and');
      expect(ids(), ['b', 'c', 'a']);
      expect(store.recipesMatching(prefs).map((r) => r.id), ['c']);
    },
  );

  test('chicken rise keeps chicken-only rows below the full match', () async {
    await setup([
      searchRecipe('a', 'Chicken rice'),
      searchRecipe('b', 'Chicken rise'),
      searchRecipe('c', 'Chicken'),
      searchRecipe('d', 'Rice'),
    ]);
    prefs.setQuery('chicken rise');
    expect(ids(), ['b', 'a', 'c']);
    expect(store.partialMatchStart, 1);
    expect(store.recipesMatching(prefs).map((r) => r.id), ['b']);
  });

  test(
    'repeated phrase words retain their role in equivalent phrases',
    () async {
      await setup([
        searchRecipe('a', 'Scallion'),
        searchRecipe('b', 'Green onion'),
        searchRecipe('c', 'Green'),
      ]);
      prefs.setQuery('green onion spring onion');
      expect(ids(), ['b', 'a', 'c']);
      expect(store.partialMatchStart, 2);
      expect(store.recipesMatching(prefs).map((r) => r.id), ['b', 'a']);
      prefs.setQuery('green lime onion');
      expect(ids(), ['b', 'c']);
      expect(store.fullMatchCount, 0);
      expect(store.recipesMatching(prefs), isEmpty);
    },
  );

  test(
    'punctuation-only and quoted searches preserve literal substrings',
    () async {
      await setup([
        searchRecipe('a', 'Rice'),
        searchRecipe('b', 'A [rice] bowl'),
        searchRecipe('c', 'Use "rice"'),
      ]);
      for (final (query, id) in [
        ('[', 'b'),
        ('[rice]', 'b'),
        ('"rice"', 'c'),
      ]) {
        prefs.setQuery(query);
        expect(ids(), [id]);
        expect(store.recipesMatching(prefs).single.id, id);
      }
    },
  );
  test('results ready in notification; builds, scroll and view changes reuse cache', () async {
    await setup(searchScreenshotsRecipes());
    var calls = 0;
    store.addListener(() {
      calls++;
      expect(ids(), ['a', 'b', 'c']);
    });
    prefs.setQuery('chicken rice');
    expect(calls, 1);
    final cached = store.visibleRecipes;
    for (var i = 0; i < 20; i++) {
      prefs.setScrollOffset(i * 30);
      expect(identical(store.visibleRecipes, cached), true);
    }
    prefs.setView(RecipeView.compact);
    expect(identical(store.visibleRecipes, cached), true);
    expect(repository.detailCalls, 0);
    expect(repository.snapshotCalls, 1);
  });
}
