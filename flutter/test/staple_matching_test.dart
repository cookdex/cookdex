import 'package:cookdex/staple_matching.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const examples = {
    'salt': [
      'kosher salt',
      'sea salt',
      'salt, kosher',
      'salt (fine sea)',
      'a pinch of salt',
      'salt to taste',
    ],
    'pepper': [
      'freshly ground black pepper',
      'pepper, freshly ground',
      'black peppercorns',
      'black peppercorns (whole)',
      'whole black peppercorns',
      'pepper (ground)',
    ],
    'oil': [
      'vegetable oil',
      'extra-virgin olive oil',
      'oil (olive)',
      'canola oil',
      'corn oil',
      'vegetable or extra-virgin olive oil',
      'sunflower, vegetable, rice bran or rapeseed oil',
    ],
    'olive oil': ['extra virgin olive oil', 'olive oil, for frying'],
    'butter': [
      'unsalted butter',
      'butter, unsalted',
      'butter, melted and cooled',
      '2 sticks butter',
      'butter, softened to room temperature',
    ],
    'flour': [
      'all-purpose flour',
      'all purpose flour',
      'plain flour',
      'flour, sifted',
      'flour (all-purpose)',
      'flour, all-purpose',
      '500 g plain flour (100%)',
      'flour, sifted before measuring',
      'flour (150 g)',
    ],
    'sugar': [
      'granulated sugar',
      'white sugar',
      'sugar, granulated',
      'caster sugar',
      'sugar (white)',
    ],
    'basic spices': [
      'ground cumin',
      'cumin, ground',
      'cayenne pepper',
      'smoked paprika',
      'dried thyme',
      'crushed red pepper flakes',
    ],
    'rice': [
      'steamed rice',
      'cooked rice',
      'rice, cooked',
      'rice (steamed)',
      'white rice',
      'long-grain rice',
      'jasmine rice',
      'basmati rice',
      'white long-grain rice',
      'rice, white long-grain',
      'white jasmine rice',
      'white basmati rice, cooked and cooled',
      'rice (2 cups uncooked, 370 g)',
    ],
    'eggs': [
      'large eggs',
      'egg, large',
      '2 extra-large eggs',
      'eggs (large), beaten',
    ],
  };
  for (final entry in examples.entries) {
    for (final food in entry.value) {
      test('${entry.key} covers $food', () {
        expect(isStaple(food, [entry.key]), isTrue);
        expect(stapleMatchesFood(entry.key, food), isTrue);
        expect(isStaple('  ${food.toUpperCase()}  ', [entry.key]), isTrue);
      });
    }
  }
  const different = {
    'salt': ['garlic salt', 'salted peanuts'],
    'pepper': [
      'bell pepper',
      'cayenne pepper',
      'jalapeño pepper',
      'peppers',
      '2 peppers',
      'fresh pepper',
    ],
    'butter': ['peanut butter', 'buttermilk', 'butter beans'],
    'sugar': [
      'brown sugar',
      'powdered sugar',
      'golden caster sugar',
      'raw sugar',
    ],
    'rice': [
      'rice vinegar',
      'rice noodles',
      'rice flour',
      'brown rice',
      'wild rice',
      'arborio rice',
      'sushi rice',
    ],
    'flour': [
      'rice flour',
      'almond flour',
      'bread flour',
      'self-raising flour',
      'whole wheat flour',
    ],
    'oil': ['sesame oil', 'coconut oil', 'avocado oil', 'oil-packed tomatoes'],
    'olive oil': ['vegetable oil', 'sesame oil'],
    'milk': ['coconut milk'],
    'cream': ['cream cheese'],
    'potato': ['sweet potato', 'sweet potatoes'],
    'basic spices': [
      'fresh cumin leaves',
      'fresh thyme',
      'fresh ginger',
      'fresh turmeric',
      'taco seasoning',
      'Italian seasoning',
    ],
    'eggs': ['egg whites', 'egg yolks', 'egg noodles'],
  };
  for (final entry in different.entries) {
    for (final food in entry.value) {
      test('${entry.key} does not cover $food', () {
        expect(isStaple(food, [entry.key]), isFalse);
        expect(stapleMatchesFood(entry.key, food), isFalse);
      });
    }
  }
  test('compound rows require every food, and restock finds each part', () {
    for (final food in [
      'salt and pepper',
      'salt & pepper',
      'salt, pepper',
      'a pinch of sea salt and freshly ground black pepper',
    ]) {
      expect(staplesCoveringFood(food, ['salt', 'pepper']), ['salt', 'pepper']);
      expect(isStaple(food, ['salt']), isFalse);
      expect(stapleMatchesFood('salt', food), isTrue);
      expect(stapleMatchesFood('pepper', food), isTrue);
    }
    expect(isStaple('cooked rice and broccoli', ['rice']), isFalse);
    expect(isStaple('salt or pepper', ['salt']), isFalse);
    expect(isStaple('salt and bell pepper', ['salt', 'pepper']), isFalse);
    expect(isStaple('rice (with 100 g peas)', ['rice']), isFalse);
    expect(isStaple('salt (plus 1 tbsp soy sauce)', ['salt']), isFalse);
    expect(isStaple('flour (100 g rice flour)', ['flour']), isFalse);
    for (final food in [
      'corn and oil',
      'corn and olive oil',
      'corn, olive oil',
      'corn or olive oil',
      'rice and oil',
      'rice, oil',
      'oil, corn',
      'vegetable oil, 100 g corn, drained',
      'oil, olives',
    ]) {
      expect(isStaple(food, ['oil']), isFalse, reason: food);
    }
  });
  test('exact custom food aliases survive in both directions', () {
    for (final pair in [
      ['icing sugar', 'powdered sugar'],
      ['garbanzo beans', 'chickpeas'],
      ['yoghurt', 'yogurt'],
      ['capsicum', 'bell peppers'],
      ['cheddar cheese', 'cheddar'],
      ['coriander leaves', 'cilantro'],
      ['spring onions', 'scallions'],
    ]) {
      expect(isStaple(pair.first, [pair.last]), isTrue);
      expect(isStaple(pair.last, [pair.first]), isTrue);
      expect(stapleMatchesFood(pair.first, pair.last), isTrue);
      expect(stapleMatchesFood(pair.last, pair.first), isTrue);
    }
    expect(isStaple('powdered sugar', ['sugar']), isFalse);
    expect(isStaple('capsicum', ['pepper']), isFalse);
  });
  test('saved specific products still match themselves without broadening', () {
    for (final food in [
      'bread flour',
      'brown rice',
      'sesame oil',
      'peanut butter',
      'cream cheese',
    ]) {
      expect(isStaple(food, [food]), isTrue);
    }
    expect(isStaple('white rice', ['jasmine rice']), isFalse);
    expect(isStaple('olive oil', ['vegetable oil']), isFalse);
    expect(isStaple('', ['salt']), isFalse);
    expect(isStaple('to taste', ['salt']), isFalse);
  });
}
