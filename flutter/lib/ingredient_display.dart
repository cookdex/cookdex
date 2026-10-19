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
  final package = RegExp(
    r'^\(([^)]+)\)\s*(cans?|jars?|bottles?|boxes|box|bags?|packages?)$',
    caseSensitive: false,
  ).firstMatch(ingredient.unit.trim());
  if (package != null && package.group(1)!.trim().isNotEmpty) {
    final rawContainer = package.group(2)!.toLowerCase();
    final container = rawContainer == 'boxes'
        ? 'box'
        : rawContainer.endsWith('s')
        ? rawContainer.substring(0, rawContainer.length - 1)
        : rawContainer;
    final suffix = plural ? (container == 'box' ? 'es' : 's') : '';
    return '(${package.group(1)}) $container$suffix';
  }
  if (plural) {
    return switch (ingredient.unit) {
      'cup' ||
      'clove' ||
      'slice' ||
      'sprig' ||
      'stalk' ||
      'head' ||
      'can' ||
      'jar' ||
      'bottle' ||
      'bag' ||
      'package' => '${ingredient.unit}s',
      'box' => 'boxes',
      'bunch' => 'bunches',
      'pinch' => 'pinches',
      _ => ingredient.unit,
    };
  }
  return ingredient.unit;
}
