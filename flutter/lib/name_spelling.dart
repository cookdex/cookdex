import 'name_matching.dart';

bool _pluralWord(String singular, String plural) {
  if (plural == '${singular}s') return true;
  const irregular = {
    'leaf': 'leaves',
    'loaf': 'loaves',
    'half': 'halves',
    'knife': 'knives',
    'wife': 'wives',
    'life': 'lives',
    'calf': 'calves',
    'shelf': 'shelves',
    'goose': 'geese',
    'foot': 'feet',
    'tooth': 'teeth',
    'mouse': 'mice',
    'child': 'children',
    'person': 'people',
    'ox': 'oxen',
  };
  if (irregular[singular] == plural) return true;
  if (singular.endsWith('y') &&
      singular.length > 1 &&
      !'aeiou'.contains(singular[singular.length - 2]) &&
      plural == '${singular.substring(0, singular.length - 1)}ies') {
    return true;
  }
  if (['s', 'x', 'z', 'ch', 'sh', 'o', 'i'].any(singular.endsWith) &&
      plural == '${singular}es') {
    return true;
  }
  return false;
}

bool _pluralWords(List<String> singular, List<String> plural) {
  if (singular.length != plural.length) return false;
  var changed = false;
  for (var i = 0; i < singular.length; i++) {
    if (singular[i] == plural[i]) continue;
    if (!_pluralWord(singular[i], plural[i])) return false;
    changed = true;
  }
  return changed;
}

bool pluralNameOf(String singular, String plural) => _pluralWords(
  sameNameKey(singular).split(' '),
  sameNameKey(plural).split(' '),
);
bool singularPluralNames(String a, String b) =>
    pluralNameOf(a, b) || pluralNameOf(b, a);

/// Prepared once per stored spelling, shared by duplicate groups and pickers.
class NameSpelling {
  NameSpelling(String name) : key = sameNameKey(name) {
    letters = _letters.allMatches(key).length;
    runes = key.runes.toList(growable: false);
    for (final rune in runes) {
      runeMask |= 1 << (rune % 32);
    }
    words = key.split(' ');
    numbers = _numbers.allMatches(key).map((m) => m[0]).join('|');
  }
  final String key;
  int runeMask = 0;
  late final int letters;
  late final List<int> runes;
  late final List<String> words;
  late final String numbers;
  static final _letters = RegExp(r'\p{Letter}', unicode: true);
  static final _numbers = RegExp(r'\p{Number}+', unicode: true);
  bool sameOrSimilar(NameSpelling other) {
    if (key.isEmpty || other.key.isEmpty) return false;
    if (key == other.key) return true;
    if (letters <= 3 || other.letters <= 3 || numbers != other.numbers) {
      return false;
    }
    final limit = letters >= 10 || other.letters >= 10 ? 2 : 1;
    // Every edit can change at most two character-presence bits. Collisions
    // only admit extra candidates; they cannot discard a valid near spelling.
    var difference = runeMask ^ other.runeMask;
    var bits = 0;
    while (difference != 0) {
      difference &= difference - 1;
      if (++bits > limit * 2) return false;
    }
    if (_pluralWords(words, other.words) || _pluralWords(other.words, words)) {
      return false;
    }
    return _withinEdits(runes, other.runes, limit);
  }
}

/// Banded optimal-string-alignment distance: insert, delete, substitute or
/// transpose adjacent characters. Rows outside the small edit budget are skipped.
bool _withinEdits(List<int> a, List<int> b, int limit) {
  if ((a.length - b.length).abs() > limit) return false;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var beforePrevious = previous;
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, limit + 1);
    row[0] = i;
    final from = (i - limit).clamp(1, b.length);
    final to = (i + limit).clamp(1, b.length);
    var best = limit + 1;
    for (var j = from; j <= to; j++) {
      var cost = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      if (previous[j] + 1 < cost) cost = previous[j] + 1;
      if (row[j - 1] + 1 < cost) cost = row[j - 1] + 1;
      if (i > 1 &&
          j > 1 &&
          a[i - 1] == b[j - 2] &&
          a[i - 2] == b[j - 1] &&
          beforePrevious[j - 2] + 1 < cost) {
        cost = beforePrevious[j - 2] + 1;
      }
      row[j] = cost;
      if (cost < best) best = cost;
    }
    if (best > limit) return false;
    beforePrevious = previous;
    previous = row;
  }
  return previous[b.length] <= limit;
}
