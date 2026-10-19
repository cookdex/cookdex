import 'package:cookdex/ingredient_display.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sized container display follows count and preserves the size', () {
    for (final entry in {
      'can': 'cans',
      'jar': 'jars',
      'bottle': 'bottles',
      'box': 'boxes',
      'bag': 'bags',
      'package': 'packages',
    }.entries) {
      for (final suffix in [entry.key, entry.value]) {
        for (final amount in [
          const Amount.rational(numerator: 1, denominator: 2),
          const Amount.rational(numerator: 1, denominator: 1),
          const Amount.rational(numerator: 2, denominator: 1),
          const Amount.range(
            lowerNumerator: 1,
            lowerDenominator: 1,
            upperNumerator: 2,
            upperDenominator: 1,
          ),
        ]) {
          final plural =
              amount is Amount_Range ||
              (amount is Amount_Rational &&
                  amount.numerator > amount.denominator);
          final ingredient = Ingredient(
            amount: amount,
            unit: '(14 OZ) $suffix',
            name: 'tomatoes',
            prepNote: '',
            optional: false,
            section: '',
          );
          expect(
            displayIngredientUnit(ingredient),
            '(14 OZ) ${plural ? entry.value : entry.key}',
          );
          expect(ingredient.unit, '(14 OZ) $suffix');
        }
      }
    }
  });
  test(
    'count units pluralize for ranges and counts without changing source',
    () {
      for (final entry in {
        'clove': 'cloves',
        'slice': 'slices',
        'sprig': 'sprigs',
        'stalk': 'stalks',
        'head': 'heads',
        'bunch': 'bunches',
      }.entries) {
        for (final amount in [
          const Amount.rational(numerator: 3, denominator: 1),
          const Amount.range(
            lowerNumerator: 1,
            lowerDenominator: 1,
            upperNumerator: 2,
            upperDenominator: 1,
          ),
        ]) {
          final row = Ingredient(
            amount: amount,
            unit: entry.key,
            name: 'herbs',
            prepNote: '',
            optional: false,
            section: '',
          );
          expect(displayIngredientUnit(row), entry.value);
          expect(row.unit, entry.key);
          expect(
            displayIngredientUnit(
              Ingredient(
                amount: const Amount.rational(numerator: 1, denominator: 2),
                unit: row.unit,
                name: row.name,
                prepNote: '',
                optional: false,
                section: '',
              ),
            ),
            entry.key,
          );
        }
      }
    },
  );
}
