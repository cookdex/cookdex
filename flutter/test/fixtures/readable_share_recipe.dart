import 'package:cookdex/src/rust/api.dart';

Recipe readableShareRecipe({
  String id = 'readable-share',
  String title = 'Lemon oat pancakes',
  String servings = '4',
  String source = 'https://example.org/lemon-oat-pancakes',
  bool favorite = true,
}) => Recipe(
  id: id,
  favorite: favorite,
  revision: 7,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-07',
  fields: RecipeFields(
    title: title,
    description: 'Tender pancakes with a bright lemon finish.',
    servings: servings,
    prepTime: '10 min',
    cookTime: '15 min',
    totalTime: '25 min',
    source: source,
    tags: const ['breakfast', 'weekend'],
    notes:
        'Make the batter just before cooking.\n\n'
        'Chill leftovers for tomorrow. Reheat gently.',
    ingredients: const [
      Ingredient(
        amount: Amount.rational(numerator: 1, denominator: 1),
        unit: '',
        name: 'lemon',
        prepNote: 'zested',
        optional: false,
        section: '',
      ),
      Ingredient(
        amount: Amount.rational(numerator: 3, denominator: 2),
        unit: 'cup',
        name: 'oat flour',
        prepNote: '',
        optional: false,
        section: 'Batter',
      ),
      Ingredient(
        amount: Amount.range(
          lowerNumerator: 3,
          lowerDenominator: 4,
          upperNumerator: 5,
          upperDenominator: 4,
        ),
        unit: 'cup',
        name: 'milk',
        prepNote: 'add as needed',
        optional: false,
        section: 'Batter',
      ),
      Ingredient(
        amount: Amount.toTaste(),
        unit: '',
        name: 'salt',
        prepNote: '',
        optional: false,
        section: 'Batter',
      ),
      Ingredient(
        amount: Amount.rational(numerator: 1, denominator: 3),
        unit: 'cup',
        name: 'berries',
        prepNote: 'washed',
        optional: true,
        section: 'To serve',
      ),
    ],
    steps: const [
      'Mix the batter: Stir the flour, milk, salt and lemon zest until combined.',
      'Cook: Spoon into a warm pan. Turn when bubbles form; cook until golden.',
      'Serve: Top with the berries.',
    ],
  ),
);
