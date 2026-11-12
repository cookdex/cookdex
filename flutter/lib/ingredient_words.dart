import 'search_accents.dart';

const recipeSearchSynonyms = [
  ['scallion', 'green onion', 'spring onion'],
  ['chickpea', 'garbanzo'],
  ['zucchini', 'courgette'],
  ['eggplant', 'aubergine'],
  ['bell pepper', 'capsicum'],
  ['arugula', 'rocket'],
  ['shrimp', 'prawn'],
  ['powdered sugar', 'icing sugar', "confectioners' sugar"],
];

final _token = RegExp(
  r"[\p{L}\p{M}\p{N}]+(?:['’\p{Pd}][\p{L}\p{M}\p{N}]+)*['’]?|&",
  unicode: true,
);
final _dash = RegExp(r'\p{Pd}', unicode: true);
final _apostrophe = RegExp("['’]");
final searchLettersOnly = RegExp(r'^\p{L}+$', unicode: true);
List<String> searchWords(String value) =>
    _token.allMatches(value).map((m) => m[0]!).toList();

String foldSearchWord(String word) => word == '&'
    ? 'and'
    : foldSearchAccents(
        word.replaceAll(_apostrophe, '').replaceAll(_dash, ' '),
      );

const _irregularEndings = {
  'leaf': 'leaves',
  'loaf': 'loaves',
  'knife': 'knives',
  'half': 'halves',
  'shelf': 'shelves',
  'calf': 'calves',
  'wolf': 'wolves',
  'life': 'lives',
  'wife': 'wives',
  'thief': 'thieves',
  'potato': 'potatoes',
  'tomato': 'tomatoes',
};
final _consonantY = RegExp(r'[b-df-hj-np-tv-z]y$');
final _sibilant = RegExp(r'(s|x|z|ch|sh)$');
final _pluralToSingular = {
  for (final e in _irregularEndings.entries) e.value: e.key,
};
final _alreadyPlural = RegExp(r'(ies|oes|ches|shes|sses|xes|zzes)$');

String? _plural(String word) {
  if (_irregularEndings[word] case final plural?) return plural;
  if (_pluralToSingular.containsKey(word) || _alreadyPlural.hasMatch(word)) {
    return null;
  }
  if (_consonantY.hasMatch(word)) {
    return '${word.substring(0, word.length - 1)}ies';
  }
  // A plain final s usually already marks a plural (beans, onions).
  if (word.endsWith('s') && !word.endsWith('ss') && !word.endsWith('us')) {
    return null;
  }
  return _sibilant.hasMatch(word) ? '${word}es' : '${word}s';
}

Iterable<String> searchNumberForms(String word) sync* {
  yield word;
  if (word.length < 2 || !searchLettersOnly.hasMatch(word)) return;
  if (_plural(word) case final plural?) yield plural;
  if (_pluralToSingular[word] case final singular?) {
    yield singular;
    return;
  }
  if (!word.endsWith('s')) return;
  final stems = [
    if (!word.endsWith('ss') && !word.endsWith('us'))
      word.substring(0, word.length - 1),
    if (word.endsWith('es')) word.substring(0, word.length - 2),
    if (word.endsWith('ies')) '${word.substring(0, word.length - 3)}y',
  ];
  for (final stem in stems) {
    if (stem.length >= 2 && _plural(stem) == word) yield stem;
  }
}

Iterable<String> searchPhraseForms(String phrase) sync* {
  final split = phrase.lastIndexOf(' ') + 1;
  for (final last in searchNumberForms(phrase.substring(split))) {
    yield phrase.substring(0, split) + last;
  }
}
