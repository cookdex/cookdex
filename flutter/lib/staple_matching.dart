import 'ingredient_words.dart';

// Pantry identity is deliberately narrower than word overlap. Keep ingredient
// substitutions and Foods to avoid independent from these local staple rules.
String _singular(String word) {
  final forms = searchNumberForms(word)
      .where((s) => s.length < word.length)
      .toList();
  if (forms.isEmpty) return word;
  if (word.endsWith('ies')) {
    return forms.firstWhere((s) => s.endsWith('y'), orElse: () => forms.first);
  }
  forms.sort((a, b) => a.length.compareTo(b.length));
  return forms.first;
}

String _fold(String value) =>
    searchWords(value.toLowerCase())
        .expand((s) => foldSearchWord(s).split(' '))
        .map(_singular)
        .join(' ');

const _units = {
  'g',
  'gram',
  'kg',
  'kilogram',
  'mg',
  'ml',
  'milliliter',
  'millilitre',
  'l',
  'liter',
  'litre',
  'cup',
  'c',
  'tbsp',
  'tbs',
  'tablespoon',
  'tsp',
  'teaspoon',
  'oz',
  'ounce',
  'lb',
  'pound',
  'pinch',
  'dash',
  'knob',
  'stick',
  'bag',
  'packet',
  'package',
  'box',
  'bottle',
  'jar',
  'can',
};
const _quantityWords = {
  'a',
  'an',
  'of',
  'each',
  'one',
  'two',
  'three',
  'four',
  'five',
  'six',
  'half',
  'quarter',
  'some',
  'little',
  'extra',
  'heaped',
  'heaping',
  'level',
};
const _prep = {
  'freshly',
  'finely',
  'coarsely',
  'coarse',
  'roughly',
  'cracked',
  'sifted',
  'melted',
  'softened',
  'cold',
  'chilled',
  'diced',
  'cubed',
  'chopped',
  'grated',
  'beaten',
  'peeled',
  'divided',
  'optional',
  'rinsed',
  'drained',
  'cooled',
  'spooned',
  'leveled',
  'levelled',
  'packed',
};
final _number = RegExp(r'^[\p{N}./]+$', unicode: true);
final _price = RegExp(r'\$\s*\d+(?:\.\d+)?\**');
final _aside = RegExp(r'\(([^()]*)\)');
const _measureUnits = {
  'g',
  'gram',
  'kg',
  'kilogram',
  'ml',
  'milliliter',
  'millilitre',
  'l',
  'liter',
  'litre',
  'oz',
  'ounce',
  'lb',
  'pound',
  'cup',
  'tbsp',
  'tablespoon',
  'tsp',
  'teaspoon',
  'fl',
};
String _withoutMeasureAside(Match match) {
  final words = _fold(
    match[1]!.replaceAllMapped(
      RegExp(r'(\d)([a-zA-Z])'),
      (m) => '${m[1]} ${m[2]}',
    ),
  ).split(' ');
  // An alternate amount may include preparation, but never discard another
  // food merely because it appears beside a measured quantity.
  final measureOnly =
      words.any(_number.hasMatch) &&
      words.any(_measureUnits.contains) &&
      words.every(
        (s) =>
            _number.hasMatch(s) ||
            _measureUnits.contains(s) ||
            _prep.contains(s) ||
            const {
              'about',
              'approx',
              'approximately',
              'total',
              'to',
              'cooked',
              'uncooked',
              'steamed',
              'raw',
            }.contains(s),
      );
  return measureOnly ? '' : match[0]!;
}

final _exactAliases = {
  for (final group in ingredientFoodAliases)
    for (final alias in group) _fold(alias): _fold(group.first),
};
final _noteAside = RegExp(
  r'\(\s*(?:see\s+)?notes?\s*\d*\s*\)',
  caseSensitive: false,
);
final _percentAside = RegExp(r'\(\s*\d+(?:[.,]\d+)?\s*%\s*\)');
final _prepPhrase = RegExp(
  r'\b(?:(?:or )?to taste|as needed|(?:(?:at|to) )?room temperature|(?:before|after) measuring|cut (?:in|into) (?:small )?(?:pieces|cubes)|'
  r'plus (?:a knob|extra|more)(?:\s+(?:for|to)\s+(?:dusting|serving|serve|greasing|brushing))?|'
  r'(?:for|to) (?:dusting|serving|serve|greasing|brushing|frying|cooking))\b',
  caseSensitive: false,
);
final _extraMeasure = RegExp(
  r'\bplus\s+\d+(?:[./]\d+)?\s*(?:tsp|tbsp|teaspoons?|tablespoons?|cups?|g|ml)\s+'
  r'for (?:the )?(?:marinade|batter|pan|frying|dusting|greasing)\s*$',
  caseSensitive: false,
);
final _heatAside = RegExp(
  r'\(\s*depending on (?:how hot you like it|taste)\s*\)',
  caseSensitive: false,
);

/// Components stay separate: having salt alone cannot hide "salt and pepper".
/// Preparation-only components ("melted and cooled") carry no extra food.
List<String> stapleFoodParts(String food) {
  final cleaned = food
      .replaceAll(_price, '')
      .replaceAllMapped(_aside, _withoutMeasureAside)
      .replaceAll(_noteAside, '')
      .replaceAll(_percentAside, '')
      .replaceAll(_prepPhrase, '')
      .replaceAll(_extraMeasure, '')
      .replaceAll(_heatAside, '')
      .replaceAll(
        RegExp(r'\(\s*(?:such as|e\.g\.)\s*', caseSensitive: false),
        ' or ',
      );
  final chunks = <String>[];
  for (final clause in cleaned.split(
    RegExp(r'\s+(?:and|or)\s+|\s*&\s*', caseSensitive: false),
  )) {
    final clauseChunks = <String>[];
    for (final part in clause.split(',')) {
      final joined = clauseChunks.isEmpty ? '' : '${clauseChunks.last} $part';
      final identity = _identity(joined);
      // A comma may introduce a descriptor ("flour, all-purpose") or a
      // second food ("salt, pepper"). Merge only a recognized whole product.
      if (clauseChunks.isNotEmpty &&
          _knownProduct(_identity(clauseChunks.last)) &&
          !const {'corn', 'rice bran', 'olive'}.contains(_identity(part)) &&
          _knownProduct(identity)) {
        clauseChunks[clauseChunks.length - 1] = joined;
      } else {
        clauseChunks.add(part);
      }
    }
    chunks.addAll(clauseChunks);
  }
  final parts = chunks.map(_identity).where((s) => s.isNotEmpty).toList();
  const oilDescriptors = {
    'vegetable',
    'canola',
    'rapeseed',
    'sunflower',
    'rice bran',
    'olive',
  };
  final sharedOil =
      RegExp(r'\bor\b', caseSensitive: false).hasMatch(cleaned) &&
      !RegExp(r'\band\b|&', caseSensitive: false).hasMatch(cleaned) &&
      parts.any((p) => p.startsWith('oil:')) &&
      parts.every(
        (p) => p == 'oil' || p.startsWith('oil:') || oilDescriptors.contains(p),
      );
  return parts
      .map(
        (part) => sharedOil && oilDescriptors.contains(part)
            ? _identity('$part oil')
            : part,
      )
      .where((s) => s.isNotEmpty)
      .toList();
}

String _identity(String raw) {
  var folded = _fold(raw);
  final countedPepper = RegExp(
    r'^(?:\d+|[¼½¾]|one|two|three|a|an)\s+(?:(?:large|small|medium)\s+)?peppers?\b',
    caseSensitive: false,
  ).hasMatch(raw.trim());
  final vegetablePepper =
      RegExp(
        r'\b(?:fresh|frozen|raw|large|small|medium|diced|chopped|sliced)\b',
      ).hasMatch(folded) ||
      RegExp(r'\bpeppers\b', caseSensitive: false).hasMatch(raw);
  // Quantity tokens do not identify a product; numbers elsewhere are retained.
  folded = folded.replaceFirstMapped(
    RegExp(r'^([0-9]+)(g|kg|ml|l)\b'),
    (m) => '${m[1]} ${m[2]}',
  );
  final words = folded.split(' ').where((s) => s.isNotEmpty).toList();
  while (words.isNotEmpty &&
      (_number.hasMatch(words.first) ||
          _units.contains(words.first) ||
          _quantityWords.contains(words.first))) {
    words.removeAt(0);
  }
  final value = words.where((s) => !_prep.contains(s)).join(' ').trim();
  if (value.isEmpty) return '';
  bool only(String noun, Set<String> descriptors) {
    final tokens = value.split(' ');
    return tokens.contains(noun) &&
        tokens.every((s) => s == noun || descriptors.contains(s));
  }

  if (only('salt', {
    'kosher',
    'sea',
    'table',
    'fine',
    'flaky',
    'flake',
    'iodized',
    'iodised',
    'diamond',
    'crystal',
    'morton',
  })) {
    return 'salt';
  }
  if (only('pepper', {'black', 'ground', 'table'}) ||
      only('peppercorn', {'black', 'ground', 'whole'})) {
    if (!value.contains('black') &&
        !value.contains('ground') &&
        (countedPepper || vegetablePepper)) {
      return 'vegetable pepper';
    }
    return 'pepper';
  }
  if (only('butter', {
    'salted',
    'unsalted',
    'slightly',
    'cultured',
    'european',
    'style',
    'browned',
  })) {
    return 'butter';
  }
  if (only('flour', {
    'all',
    'purpose',
    'plain',
    'white',
    'bleached',
    'unbleached',
    'enriched',
    'king',
    'arthur',
  })) {
    return 'flour';
  }
  if (only('sugar', {
    'granulated',
    'white',
    'caster',
    'castor',
    'superfine',
    'table',
  })) {
    return 'sugar';
  }
  if (only('egg', {
    'large',
    'small',
    'medium',
    'extra',
    'jumbo',
    'whole',
    'fresh',
  })) {
    return 'egg';
  }
  if (only('oil', {'cooking', 'neutral', 'flavourless', 'flavorless'})) {
    return 'oil';
  }
  if (only('oil', {'olive', 'extra', 'virgin', 'light', 'pure', 'refined'})) {
    return 'oil:olive';
  }
  if ((!value.split(' ').contains('rice') ||
          value.split(' ').contains('bran')) &&
      only('oil', {
        'vegetable',
        'canola',
        'rapeseed',
        'sunflower',
        'corn',
        'rice',
        'bran',
        'cooking',
        'neutral',
        'refined',
      })) {
    return 'oil:neutral';
  }
  final rice = value
      .split(' ')
      .where(
        (s) => !{
          'cooked',
          'steamed',
          'uncooked',
          'raw',
          'leftover',
          'freshly',
        }.contains(s),
      )
      .join(' ');
  if (rice == 'rice') return 'rice';
  final riceWords = rice.split(' ');
  bool riceOnly(Set<String> descriptors) =>
      riceWords.contains('rice') &&
      riceWords.every((s) => s == 'rice' || descriptors.contains(s));
  if (riceOnly({'white', 'long', 'short', 'grain'})) return 'rice:white';
  if (riceOnly({'jasmine', 'white'})) return 'rice:jasmine';
  if (riceOnly({'basmati', 'white'})) return 'rice:basmati';
  if (rice != value && value.split(' ').contains('rice')) return rice;
  if (value == 'basic spice') return 'basic spices';
  return _exactAliases[value] ?? value;
}

bool _knownProduct(String value) =>
    const {
      'salt',
      'pepper',
      'butter',
      'flour',
      'sugar',
      'egg',
      'oil',
      'oil:olive',
      'oil:neutral',
      'rice',
      'rice:white',
      'rice:jasmine',
      'rice:basmati',
    }.contains(value) ||
    _drySpice(value);

bool _drySpice(String name) {
  final words = name.replaceAll('chilli', 'chili').split(' ');
  bool only(String noun, Set<String> allowed) =>
      words.contains(noun) &&
      words.every((s) => s == noun || allowed.contains(s));
  if (only('paprika', {'sweet', 'smoked', 'hot', 'ground'}) ||
      only('cumin', {'seed', 'ground', 'toasted'}) ||
      only('cinnamon', {'ground'}) ||
      only('nutmeg', {'ground'}) ||
      only('cayenne', {'pepper', 'powder', 'ground'}) ||
      only('turmeric', {'ground', 'powder'}) ||
      only('chili', {'powder', 'flake', 'crushed'}) && words.length > 1) {
    return true;
  }
  if (only('coriander', {'seed', 'ground'}) && words.length > 1) return true;
  if ({
    'garlic powder',
    'onion powder',
    'ground ginger',
    'ginger ground',
    'red pepper flake',
    'crushed red pepper',
    'crushed red pepper flake',
  }.contains(name)) {
    return true;
  }
  return {
    'oregano',
    'thyme',
    'basil',
    'rosemary',
  }.any((herb) => only(herb, {'dried', 'dry', 'ground'}) && words.length > 1);
}

bool _sameStaple(String staple, String food) =>
    staple == food ||
    staple == 'basic spices' && _drySpice(food) ||
    staple == 'oil' && {'oil:olive', 'oil:neutral'}.contains(food) ||
    staple == 'rice' &&
        {'rice:white', 'rice:jasmine', 'rice:basmati'}.contains(food);

/// A generated ingredient must name one actual dry seasoning, not the pantry
/// category itself or several seasonings bundled into one amount.
bool isSpecificBasicSpice(String food) {
  final parts = stapleFoodParts(food);
  return parts.length == 1 && _drySpice(parts.single);
}

/// Whether this food includes the named staple. Combined rows may include more
/// than one staple; use [isStaple] before unticking a whole ingredient row.
bool stapleMatchesFood(String staple, String food) {
  final pantry = stapleFoodParts(staple), ingredients = stapleFoodParts(food);
  return pantry.isNotEmpty &&
      ingredients.isNotEmpty &&
      pantry.every((s) => ingredients.any((f) => _sameStaple(s, f)));
}

/// Return all pantry entries covering a line, or none if any food is uncovered.
List<String> staplesCoveringFood(String food, Iterable<String> staples) {
  final parts = stapleFoodParts(food);
  if (parts.isEmpty) return const [];
  final found = <String>{};
  for (final part in parts) {
    final matches = staples.where(
      (s) => stapleFoodParts(s).any((p) => _sameStaple(p, part)),
    );
    if (matches.isEmpty) return const [];
    found.addAll(matches);
  }
  return found.toList();
}

bool isStaple(String food, Iterable<String> staples) =>
    staplesCoveringFood(food, staples).isNotEmpty;
