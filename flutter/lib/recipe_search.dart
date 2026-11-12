import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'local_preferences.dart';
import 'ingredient_words.dart';
export 'ingredient_words.dart' show recipeSearchSynonyms;
import 'src/rust/api.dart';

// Add equivalent ingredient names here. A phrase is matched within one value
// (for example, one ingredient name), including a simple plural of its last word.
const _fillerWords = {
  'and',
  'or',
  'with',
  'the',
  'of',
  'a',
  'an',
  'in',
  'for',
  'to',
};
final _space = RegExp(r'\s+');
final _foldable = RegExp(r"^[\p{L}\p{M}\p{N}'’\p{Pd}&]+$", unicode: true);

class RecipeSearchResult {
  const RecipeSearchResult(this.recipes, this.fullCount);
  final List<RecipeSummary> recipes;
  final int fullCount;
}

final _aliases = _buildAliasLookup();

Map<String, Set<String>> _buildAliasLookup() {
  final aliases = <String, Set<String>>{};
  for (final group in recipeSearchSynonyms) {
    final forms = {
      for (final name in group)
        ...searchPhraseForms(searchWords(name).map(foldSearchWord).join(' ')),
    };
    for (final form in forms) {
      aliases[form] = forms;
    }
  }
  return aliases;
}

final _longestAlias = _aliases.keys.fold(
  0,
  (n, name) => math.max(n, name.length),
);

// Source texts are shared across recipes. Postings track recipe IDs and the
// fields that actually contained this value. Phrases cannot cross ingredients.
class _Text {
  _Text(String raw) : literal = raw.toLowerCase() {
    words = [
      for (final word in searchWords(literal))
        ...foldSearchWord(word).split(' '),
    ];
  }
  final String literal;
  late final List<String> words;
  final recipes = <int, int>{};

  bool containsJoined(String joined, String first) {
    for (var i = 0; i < words.length; i++) {
      if (words[i] != first) continue;
      var offset = first.length;
      for (var j = i + 1; j < words.length && offset < joined.length; j++) {
        if (!joined.startsWith(words[j], offset)) break;
        offset += words[j].length;
        if (offset == joined.length) return true;
      }
    }
    return false;
  }
}

bool _oneEdit(List<int> a, List<int> b) {
  if (a.length > b.length) return _oneEdit(b, a);
  if (b.length - a.length > 1) return false;
  var i = 0;
  while (i < a.length && a[i] == b[i]) {
    i++;
  }
  if (i == a.length) return a.length != b.length;
  var j = i + 1;
  if (a.length == b.length) {
    if (j < a.length && a[i] == b[j] && a[j] == b[i]) j++;
    for (; j < a.length; j++) {
      if (a[j] != b[j]) return false;
    }
  } else {
    for (; i < a.length; i++) {
      if (a[i] != b[i + 1]) return false;
    }
  }
  return true;
}

class RecipeSearchIndex {
  RecipeSearchIndex(this.onReady);
  final void Function() onReady;
  final _texts = <String, _Text>{};
  final _words = <String, Set<_Text>>{};
  final _byLength = <int, Map<String, List<int>>>{};
  final _pending = <String, RecipeSummary>{};
  final _slots = <String, int>{};
  final _freeSlots = <int>[];
  int _capacity = 0;
  int _longestWord = 0;
  Timer? _warm;

  void queue(RecipeSummary recipe) => _pending[recipe.id] = recipe;

  Iterable<(String, SearchField)> _fields(RecipeSummary r) sync* {
    yield (r.title, SearchField.title);
    yield (r.notes, SearchField.notes);
    yield (r.description, SearchField.description);
    for (final value in r.tags) {
      yield (value, SearchField.tags);
    }
    for (final value in r.ingredients) {
      yield (value, SearchField.ingredients);
    }
  }

  void remove(RecipeSummary recipe) {
    _pending.remove(recipe.id);
    final slot = _slots.remove(recipe.id);
    if (slot == null) return;
    _freeSlots.add(slot);
    for (final (raw, _) in _fields(recipe)) {
      final text = _texts[raw];
      if (text == null) continue;
      text.recipes.remove(slot);
      if (text.recipes.isNotEmpty) continue;
      _texts.remove(raw);
      for (final word in text.words.toSet()) {
        final occurrences = _words[word]!..remove(text);
        if (occurrences.isEmpty) {
          _words.remove(word);
          _byLength[word.runes.length]?.remove(word);
        }
      }
    }
  }

  _Text _indexText(String raw) {
    final text = _Text(raw);
    for (final word in text.words.toSet()) {
      _words
          .putIfAbsent(word, () {
            _longestWord = math.max(_longestWord, word.length);
            final letters = word.runes.toList();
            if (letters.length >= 5 && searchLettersOnly.hasMatch(word)) {
              (_byLength[letters.length] ??= {})[word] = letters;
            }
            return {};
          })
          .add(text);
    }
    return text;
  }

  void _indexNext() {
    final r = _pending.remove(_pending.keys.first)!;
    final slot = _freeSlots.isEmpty ? _capacity++ : _freeSlots.removeLast();
    _slots[r.id] = slot;
    for (final (raw, field) in _fields(r)) {
      if (raw.isEmpty) continue;
      final text = _texts.putIfAbsent(raw, () => _indexText(raw));
      text.recipes[slot] = (text.recipes[slot] ?? 0) | (1 << field.index);
    }
  }

  void warm() {
    if (_warm != null) return;
    if (_pending.isEmpty) {
      onReady();
      return;
    }
    _warm = Timer(Duration.zero, () {
      _warm = null;
      final watch = Stopwatch()..start();
      while (_pending.isNotEmpty && watch.elapsedMicroseconds < 1800) {
        _indexNext();
      }
      warm();
    });
  }

  void dispose() => _warm?.cancel();

  // A joined word must start and end on word boundaries in one source value.
  Iterable<_Text> _joined(String word) sync* {
    yield* _words[word] ?? const <_Text>{};
    for (var cut = 1; cut < word.length && cut <= _longestWord; cut++) {
      final first = word.substring(0, cut);
      final candidates = _words[first];
      if (candidates == null) continue;
      for (final text in candidates) {
        if (text.containsJoined(word, first)) yield text;
      }
    }
  }

  Iterable<_Text> _phrase(String phrase) sync* {
    final split = phrase.indexOf(' ');
    if (split < 0) {
      yield* _words[phrase] ?? const <_Text>{};
      return;
    }
    final parts = phrase.split(' ');
    for (final text in _words[parts.first] ?? const <_Text>{}) {
      for (var i = 0; i <= text.words.length - parts.length; i++) {
        var j = 0;
        while (j < parts.length && text.words[i + j] == parts[j]) {
          j++;
        }
        if (j == parts.length) {
          yield text;
          break;
        }
      }
    }
  }

  Iterable<_Text> _aliasTexts(String phrase) sync* {
    for (final form in _aliases[phrase] ?? const <String>{}) {
      yield* _phrase(form);
    }
  }

  // Record a phrase's evidence for each term it covers. Count a distinct word
  // only once, even when single-word and overlapping phrase matches coexist.
  Map<String, Set<_Text>> _phraseMatches(
    List<String> input,
    Map<String, String> folded,
    Set<String> terms,
  ) {
    final result = <String, Set<_Text>>{};
    final limit = math.max(_longestWord, _longestAlias);
    for (var start = 0; start < input.length; start++) {
      var phrase = folded[input[start]]!;
      if (phrase.isEmpty) continue;
      var joined = phrase.replaceAll(' ', '');
      for (var end = start + 1; end < input.length; end++) {
        final next = folded[input[end]]!;
        if (next.isEmpty) break;
        final part = next.replaceAll(' ', '');
        if (joined.length + part.length > limit) break;
        joined += part;
        phrase += ' $next';
        final compound = _words[joined];
        if (compound == null && !_aliases.containsKey(phrase)) continue;
        final texts = {...?compound, ..._aliasTexts(phrase)};
        if (texts.isEmpty) continue;
        for (var i = start; i <= end; i++) {
          final term = input[i];
          if (terms.contains(term)) (result[term] ??= {}).addAll(texts);
        }
      }
    }
    return result;
  }

  // Values 1..3 encode field weight. Higher bands always win for this word:
  // 4+weight is a typo, 8+weight is equivalent, 12+weight is literal.
  void _scoreWord(
    String literal,
    String folded,
    Set<_Text>? phraseMatches,
    List<int> fieldWeights,
    Uint8List best,
  ) {
    void add(_Text text, int band) {
      for (final posting in text.recipes.entries) {
        final weight = fieldWeights[posting.value];
        if (weight != 0 && band + weight > best[posting.key]) {
          best[posting.key] = band + weight;
        }
      }
    }

    var hasLiteral = false;
    for (final text in _texts.values) {
      if (text.literal.contains(literal)) {
        hasLiteral = true; // Includes hidden fields and nonfavorites.
        add(text, 12);
      }
    }
    if (folded.isEmpty) return;
    final equivalents = {
      ...?phraseMatches,
      for (final form in searchPhraseForms(folded)) ..._phrase(form),
      ..._joined(folded.replaceAll(' ', '')),
      ..._aliasTexts(folded),
    };
    for (final text in equivalents) {
      if (!text.literal.contains(literal)) add(text, 8);
    }
    if (hasLiteral ||
        _words.containsKey(folded) ||
        !searchLettersOnly.hasMatch(folded)) {
      return;
    }
    final letters = folded.runes.toList();
    if (letters.length < 5) return;
    for (var n = letters.length - 1; n <= letters.length + 1; n++) {
      final bucket = _byLength[n];
      if (bucket == null) continue;
      for (final candidate in bucket.entries) {
        if (!_oneEdit(letters, candidate.value)) continue;
        for (final text in _words[candidate.key]!) {
          add(text, 4);
        }
      }
    }
  }

  RecipeSearchResult rank(
    List<RecipeSummary> ordered,
    LocalPreferences filters, {
    required bool picker,
  }) {
    final input = filters.query
        .toLowerCase()
        .split(_space)
        .where((s) => s.isNotEmpty)
        .toList();
    final distinct = input.toSet();
    final meaningful = picker ? distinct : distinct.difference(_fillerWords);
    final terms = meaningful.isEmpty ? distinct : meaningful;
    final allRequired = picker || meaningful.isEmpty;
    final weighted = !allRequired;
    if (terms.isEmpty || filters.searchFields.isEmpty) {
      final rows = terms.isEmpty
          ? List<RecipeSummary>.unmodifiable(
              ordered.where((r) => !filters.favoritesOnly || r.favorite),
            )
          : const <RecipeSummary>[];
      return RecipeSearchResult(rows, rows.length);
    }
    while (_pending.isNotEmpty) {
      _indexNext();
    }
    final folded = {
      for (final term in distinct)
        term: _foldable.hasMatch(term)
            ? searchWords(term).map(foldSearchWord).join(' ')
            : '',
    };
    final phrases = _phraseMatches(input, folded, terms);
    final fieldWeights = List.filled(1 << SearchField.values.length, 0);
    for (var mask = 1; mask < fieldWeights.length; mask++) {
      for (final field in filters.searchFields) {
        if ((mask & (1 << field.index)) == 0) continue;
        final weight = switch (field) {
          SearchField.title => 3,
          SearchField.tags || SearchField.ingredients => 2,
          _ => 1,
        };
        fieldWeights[mask] = math.max(weight, fieldWeights[mask]);
      }
    }
    final count = Uint32List(_capacity),
        typos = Uint32List(_capacity),
        equivalents = Uint32List(_capacity),
        weights = Uint32List(_capacity);
    final best = Uint8List(_capacity);
    for (final term in terms) {
      best.fillRange(0, best.length, 0);
      _scoreWord(term, folded[term]!, phrases[term], fieldWeights, best);
      for (var slot = 0; slot < best.length; slot++) {
        final value = best[slot];
        if (value == 0) continue;
        count[slot]++;
        if (value < 8) {
          typos[slot]++;
        } else if (value < 12) {
          equivalents[slot]++;
        }
        if (weighted) weights[slot] += value & 3;
      }
    }
    final groups = <(int, int, int, int), List<RecipeSummary>>{};
    var full = 0;
    for (final recipe in ordered) {
      if (filters.favoritesOnly && !recipe.favorite) continue;
      final slot = _slots[recipe.id]!;
      final matched = count[slot];
      if (matched == 0 || (allRequired && matched != terms.length)) continue;
      if (matched == terms.length) full++;
      final key = (matched, typos[slot], equivalents[slot], weights[slot]);
      (groups[key] ??= []).add(recipe);
    }
    // Each bucket already has the selected sort and its stable recipe-ID tie.
    final ranks = groups.keys.toList()
      ..sort((a, b) {
        var c = b.$1.compareTo(a.$1);
        if (c == 0) c = a.$2.compareTo(b.$2);
        if (c == 0) c = a.$3.compareTo(b.$3);
        return c == 0 ? b.$4.compareTo(a.$4) : c;
      });
    return RecipeSearchResult(
      List.unmodifiable([for (final key in ranks) ...groups[key]!]),
      full,
    );
  }
}
