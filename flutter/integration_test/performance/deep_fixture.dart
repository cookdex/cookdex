import 'package:cookdex/src/rust/api.dart';

const deepRecipeTitle = 'Autumn vegetable and bean stew';

/// Legacy frozen render fixture. New Cards scrolling uses mixed ZIPs produced
/// by scripts/mix_card_fixture.py; title-sorted batch copies are unrepresentative.
/// Repeat the frozen 50-recipe mix exactly, including the long recipe, rather
/// than diluting its proportion as the library grows. Only titles are unique.
RecipeFields scaleRecipeFields(int index) {
  if (index < 0 || index >= 2500) {
    throw RangeError.index(index, List.filled(2500, 0));
  }
  final source = deepRecipeFields(index % 50);
  if (index < 50) return source;
  return RecipeFields(
    title: '${source.title} (batch ${index ~/ 50 + 1})',
    description: source.description,
    servings: source.servings,
    prepTime: source.prepTime,
    cookTime: source.cookTime,
    totalTime: source.totalTime,
    source: source.source,
    tags: source.tags,
    notes: source.notes,
    ingredients: source.ingredients,
    steps: source.steps,
  );
}

/// Synthetic data only. Keep this fixture frozen throughout a measured series.
RecipeFields deepRecipeFields(int index) {
  const dishes = ['Rice', 'Soup', 'Lemon chicken', 'Roasted vegetables'];
  const names = [
    'carrots',
    'potatoes',
    'onions',
    'beans',
    'tomatoes',
    'celery',
    'spinach',
    'parsley',
    'mushrooms',
    'sweet peppers',
    'rice',
    'stock',
  ];
  final large = index == 0;
  return RecipeFields(
    title: large
        ? deepRecipeTitle
        : '${dishes[index % dishes.length]} '
              '${index % 3 == 0 ? 'with roasted seasonal vegetables, tender beans, fragrant garden herbs and a lemon dressing for the whole family ' : ''}${index + 1}',
    description: switch (index % 3) {
      0 => '',
      1 => 'An easy family meal.',
      _ =>
        'A warming everyday meal with seasonal vegetables and fresh herbs. '
            'Serve with crusty bread and a generous green salad for a relaxed supper. '
            'The leftovers make an equally satisfying lunch the next day.',
    },
    servings: index % 4 == 0 ? '' : '6 portions',
    prepTime: index % 4 == 1 ? '' : '20 min',
    cookTime: index % 4 == 1 ? '' : '40 min',
    totalTime: index % 4 == 1 ? '' : '1 hr',
    source: '',
    tags: const [
      'dinner',
      'vegetarian',
      'quick',
      'weekend',
      'family',
      'make ahead',
      'comfort food',
      'one pot',
    ].take(index % 9).toList(),
    notes: 'Prepare the vegetables ahead. Refrigerate leftovers and reheat gently.',
    ingredients: List.generate(large ? 36 : 6 + index % 12, (j) {
      final kind = j % 6;
      return Ingredient(
        amount: switch (kind) {
          0 => const Amount.rational(numerator: 2, denominator: 1),
          1 => const Amount.rational(numerator: 3, denominator: 4),
          2 => const Amount.range(
            lowerNumerator: 1,
            lowerDenominator: 2,
            upperNumerator: 3,
            upperDenominator: 2,
          ),
          3 => const Amount.rational(numerator: 250, denominator: 1),
          4 => const Amount.rational(numerator: 2, denominator: 1),
          _ => const Amount.toTaste(),
        },
        unit: switch (kind) {
          1 || 2 => 'cup',
          3 => 'g',
          4 => '(14 oz) cans',
          _ => '',
        },
        name: names[j % names.length],
        prepNote: j % 3 == 0 ? 'rinsed and finely chopped' : '',
        optional: j % 7 == 0,
        section: large
            ? const ['Vegetables', 'Sauce', 'To finish'][j ~/ 12]
            : '',
      );
    }),
    steps: List.generate(
      large ? 24 : 3 + index % 7,
      (j) =>
          '${j.isEven ? 'Prepare the vegetables: ' : ''}'
          'Warm the pan over medium heat. Add the ${names[j % names.length]} '
          'and stir until softened. Pour in the stock, cover and simmer gently for '
          '${j + 3} minutes. Taste and adjust the seasoning before continuing.'
          '${j % 3 == 0 ? ' Stir regularly, scraping the bottom gently. Keep the heat low enough to avoid scorching, and add a little water if the sauce becomes too thick. Allow the mixture to rest briefly before serving.' : ''}',
    ),
  );
}
