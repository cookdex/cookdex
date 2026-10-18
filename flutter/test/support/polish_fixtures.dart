import 'package:cookdex/src/rust/api.dart';

import '../import_test.dart' show ImportRepositoryFake;
import '../recipe_store_test.dart' show summary;

Recipe polishRecipe(String id, String title, {int tags = 5}) => Recipe(
  id: id,
  favorite: id == '0',
  revision: 1,
  createdAt: '2026-10-09',
  updatedAt: '2026-10-09',
  fields: RecipeFields(
    title: title,
    description: 'A warming family supper with tender vegetables and a rich, slow-simmered sauce.',
    servings: '4',
    prepTime: '30 min, plus proof',
    cookTime: '45 min',
    totalTime: '45 min',
    source: 'https://example.com/family-supper',
    tags: [
      'dinner',
      'family favorites',
      'slow cooker',
      'comfort food',
      'weekend',
    ].take(tags).toList(),
    notes:
        'Rest for 10 minutes before serving. Leftovers keep well for tomorrow.',
    ingredients: [
      for (final name in [
        'boneless country-style pork ribs',
        'onion',
        'carrots',
        'potatoes',
        'tomato sauce',
        'chicken broth',
        'garlic',
        'olive oil',
        'black pepper',
        'bay leaf',
      ])
        Ingredient(
          amount: const Amount.rational(numerator: 1, denominator: 1),
          unit: name.contains('ribs') ? 'lb' : '',
          name: name,
          prepNote: '',
          optional: false,
          section: '',
        ),
    ],
    steps: [
      'Pat the pork dry and season on all sides. Heat the oil in a heavy pot over medium heat until shimmering, then brown the pork in batches.',
      'Add the onion, carrots and garlic. Stir for 5 minutes, scraping the browned bits from the bottom of the pot.',
      'Return the pork to the pot with the potatoes, tomato sauce and broth. Bring to a gentle simmer, cover and cook for 45 minutes, until tender.',
      'Remove the bay leaf. Taste and adjust the seasoning, then rest for 10 minutes before serving with crusty bread.',
    ],
  ),
);

class PolishRepository extends ImportRepositoryFake {
  PolishRepository()
    : super([
        for (var i = 0; i < 12; i++)
          polishRecipe(
            '$i',
            [
              'Family pork supper',
              'Lemon & herb chicken',
              'Quick tomato soup',
              'Weekend pancakes',
              'Roasted vegetable bowl',
              'Apple cinnamon crumble',
            ][i % 6],
            tags: i % 3 == 0 ? 5 : 2,
          ),
      ]);
  @override
  CollectionSnapshot get current => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: generation,
    summaries: recipes.values.map(summary).toList(),
    shopping: [
      for (var i = 0; i < 12; i++)
        ShoppingItem(
          categoryId: 'other',
          id: 'item-$i',
          name: recipes['0']!.fields.ingredients[i % 10].name,
          measures: const [],
          contributorScales: const [],
          contributorIds: const ['0', '1', '2', '3'],
          checked: false,
          quantityText: i == 0
              ? '1 lb'
              : i == 4
              ? '14 oz'
              : '2',
        ),
    ],
    conflicts: const [],
    hasPrevious: false,
  );
  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async =>
      ingredients.map((_) => '1').toList();
}
