import 'src/rust/api.dart';

String displayIngredientUnit(Ingredient ingredient) {
  final amount = ingredient.amount;
  final plural = switch (amount) {
    Amount_Rational(:final numerator, :final denominator) =>
      numerator > denominator,
    Amount_Range(:final upperNumerator, :final upperDenominator) =>
      upperNumerator > upperDenominator,
    _ => false,
  };
  if (plural) {
    return switch (ingredient.unit) {
      'cup' || 'clove' || 'can' => '${ingredient.unit}s',
      'pinch' => 'pinches',
      _ => ingredient.unit,
    };
  }
  return ingredient.unit;
}
