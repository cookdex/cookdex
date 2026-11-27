import 'app_platform.dart' show webSourceUri;
import 'fraction_display.dart';
import 'ingredient_display.dart';
import 'release_notes.dart';
import 'src/rust/api.dart';
import 'yield_presentation.dart';

/// A readable message from saved fields, independent of the recipe's view scale.
/// Recipe files continue to use the core's exact Text v1 exporter.
String recipeShareText(Recipe recipe) {
  final fields = recipe.fields;
  final blocks = <String>[_plain(fields.title)];
  if (fields.description.trim().isNotEmpty) {
    blocks.add(_plain(fields.description));
  }
  final yieldInfo = presentRecipeYield(fields.servings);
  final metadata = <String>[
    if (yieldInfo.text.isNotEmpty)
      '${yieldInfo.isServings ? 'Serves' : 'Makes'} ${_plain(yieldInfo.text)}',
    if (fields.prepTime.trim().isNotEmpty) 'Prep ${_plain(fields.prepTime)}',
    if (fields.cookTime.trim().isNotEmpty) 'Cook ${_plain(fields.cookTime)}',
    if (fields.totalTime.trim().isNotEmpty) 'Total ${_plain(fields.totalTime)}',
  ];
  if (metadata.isNotEmpty) blocks.add(metadata.join(' · '));
  if (fields.ingredients.isNotEmpty) {
    final lines = <String>['Ingredients'];
    var section = '';
    for (final ingredient in fields.ingredients) {
      final nextSection = ingredient.section.trim();
      if (nextSection != section) {
        lines.add('');
        if (nextSection.isNotEmpty) lines.add(_plain(nextSection));
        section = nextSection;
      }
      final amount = displayFractions(_amount(ingredient.amount));
      final name = _plain(ingredient.name);
      final label = [
        if (amount.isNotEmpty) amount,
        if (ingredient.amount is! Amount_ToTaste &&
            ingredient.unit.trim().isNotEmpty)
          _plain(displayIngredientUnit(ingredient)),
        ingredient.amount is Amount_ToTaste ? '$name, to taste' : name,
      ].join(' ');
      final prep = ingredient.prepNote.trim();
      lines.add(
        '- $label${prep.isEmpty ? '' : ', ${_plain(prep)}'}'
        '${ingredient.optional ? ' (optional)' : ''}',
      );
    }
    blocks.add(lines.join('\n'));
  }
  if (fields.steps.isNotEmpty) {
    blocks.add(
      [
        'Steps',
        for (final (index, step) in fields.steps.indexed)
          '${index + 1}. ${_plain(step)}',
      ].join('\n'),
    );
  }
  if (fields.notes.trim().isNotEmpty) {
    blocks.add('Notes\n${_plain(fields.notes)}');
  }
  if (fields.source.trim().isNotEmpty) {
    final source = fields.source.trim();
    // Keep complete URLs byte-for-byte, including literal Markdown punctuation.
    blocks.add(
      'Source: ${webSourceUri(source) == null ? _plain(source) : source}',
    );
  }
  return blocks.join('\n\n');
}

// Reuse the app's inert Markdown cleanup; only presentation changes here.
String _plain(String value) =>
    plainReleaseNotes(value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));

String _amount(Amount amount) => switch (amount) {
  Amount_Rational(:final numerator, :final denominator) => _fraction(
    numerator,
    denominator,
  ),
  Amount_Range(
    :final lowerNumerator,
    :final lowerDenominator,
    :final upperNumerator,
    :final upperDenominator,
  ) =>
    '${_fraction(lowerNumerator, lowerDenominator)}–'
        '${_fraction(upperNumerator, upperDenominator)}',
  Amount_ToTaste() || Amount_Unspecified() => '',
};

String _fraction(int numerator, int denominator) {
  final whole = numerator ~/ denominator;
  final remainder = numerator % denominator;
  if (remainder == 0) return '$whole';
  final divisor = remainder.gcd(denominator);
  final fraction = '${remainder ~/ divisor}/${denominator ~/ divisor}';
  return whole == 0 ? fraction : '$whole $fraction';
}
