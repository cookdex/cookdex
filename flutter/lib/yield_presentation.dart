/// Display-only interpretation: the original recipe yield is never changed.
class RecipeYieldPresentation {
  const RecipeYieldPresentation({required this.text, required this.isServings});

  final String text;
  final bool isServings;
}

const _servingNumber =
    r'(?:\d+(?:\s+\d+/\d+|/\d+|\.\d+|\s*[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])?|[¼½¾⅐⅑⅒⅓⅔⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])';
final _servingsPattern = RegExp(
  '^(?:serves\\s+)?($_servingNumber)(?:\\s*(?:[-–—]|to)\\s*($_servingNumber))?(?:\\s+servings?)?\$',
  caseSensitive: false,
);
final _makesPrefix = RegExp(r'^makes\s+', caseSensitive: false);

RecipeYieldPresentation presentRecipeYield(String value) {
  final trimmed = value.trim().replaceFirst(_makesPrefix, '');
  final match = _servingsPattern.firstMatch(trimmed);
  if (match != null) {
    final start = match.group(1)!;
    final end = match.group(2);
    return RecipeYieldPresentation(
      text: end == null ? start : '$start–$end',
      isServings: true,
    );
  }
  return RecipeYieldPresentation(text: trimmed, isServings: false);
}
