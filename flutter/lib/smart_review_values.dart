import 'name_matching.dart';
import 'src/rust/api.dart' as core;

String reviewAmount(String text) {
  // The editor sends slash fractions through its normal rational parser on save.
  String replace(Match m) {
    final whole = int.tryParse(m[1] ?? '') ?? 0;
    final digits = m[2]!.replaceFirst(RegExp(r'0+$'), '');
    final fraction = switch (digits) {
      '125' => '1/8',
      '25' => '1/4',
      '33' || '333' || '3333' => '1/3',
      '375' => '3/8',
      '5' => '1/2',
      '625' => '5/8',
      '66' || '67' || '667' || '6667' => '2/3',
      '75' => '3/4',
      '875' => '7/8',
      _ => null,
    };
    if (fraction == null) return m[0]!;
    return whole == 0 ? fraction : '$whole $fraction';
  }

  return text.replaceAllMapped(
    RegExp(r'(?<![\w./])(\d*)\.(\d+)(?![\w./])'),
    replace,
  );
}

String _capitalize(String name) => name.isEmpty
    ? name
    : name[0].toUpperCase() + name.substring(1).toLowerCase();
String _title(String name) => name.split(' ').map(_capitalize).join(' ');

/// Source-provided tags keep their content and order. Only casing is matched.
/// A Text v1 file may deliberately contain distinct tags like Lunch and lunch.
List<String> Function(List<String>) sourceTagSpelling(
  Iterable<core.RecipeSummary> library,
) {
  final spellings = groupNameSuggestions([
    for (final r in library)
      for (final tag in r.tags)
        NameObservation(name: tag, recipeId: r.id, updatedAt: r.updatedAt),
  ], keyOf: (name) => name.toLowerCase());
  final preferred = {for (final n in spellings) n.key: n.name};
  final exact = {for (final r in library) ...r.tags};
  return (tags) {
    final byCase = <String, Set<String>>{};
    for (final tag in tags) {
      (byCase[tag.toLowerCase()] ??= {}).add(tag);
    }
    List<String>? changed;
    for (final (index, tag) in tags.indexed) {
      final key = tag.toLowerCase();
      final replacement = preferred[key];
      if (!exact.contains(tag) &&
          byCase[key]!.length == 1 &&
          replacement != null &&
          replacement != tag) {
        (changed ??= List.of(tags))[index] = replacement;
      }
    }
    return changed ?? tags;
  };
}

List<String> reviewTags(
  core.RecipeFields recipe,
  Iterable<core.RecipeSummary> library, {
  bool youtube = false,
}) {
  final preferred = groupNameSuggestions([
    for (final r in library)
      for (final tag in r.tags)
        NameObservation(name: tag, recipeId: r.id, updatedAt: r.updatedAt),
  ]);
  final spelling = {
    if (preferred.isEmpty && youtube)
      for (final tag in const [
        'Breakfast',
        'Lunch',
        'Dinner',
        'Snack',
        'Dessert',
      ])
        sameNameKey(tag): tag,
    for (final n in preferred) n.key: n.name,
  };
  final styles = <String, int>{
    'lower': 0,
    'title': 0,
    'sentence': 0,
    'upper': 0,
  };
  for (final n in preferred) {
    final s = n.name;
    final style = s == s.toLowerCase()
        ? 'lower'
        : s == s.toUpperCase()
        ? 'upper'
        : s == _title(s)
        ? 'title'
        : s == _capitalize(s)
        ? 'sentence'
        : null;
    if (style != null) styles[style] = styles[style]! + 1;
  }
  final style = styles.keys.reduce((a, b) => styles[b]! > styles[a]! ? b : a);
  final effort = RegExp(
    r'^(?:(?:very )?(?:easy|medium|hard|involved)(?:[- ](?:effort|difficulty|recipes?))?|(?:low|high)[- ]effort|beginner[- ]friendly)$',
    caseSensitive: false,
  );
  final result = <String, String>{};
  void add(String raw) {
    final name = normalizeNameWhitespace(raw), key = sameNameKey(name);
    if (name.isEmpty || name.length > 300 || effort.hasMatch(name)) return;
    result.putIfAbsent(
      key,
      () =>
          spelling[key] ??
          switch (style) {
            'title' => _title(name),
            'sentence' => _capitalize(name),
            'upper' => name.toUpperCase(),
            _ => name.toLowerCase(),
          },
    );
  }

  for (final tag in recipe.tags) {
    add(tag);
    if (result.length == 4) break;
  }
  // Use foods actually in this dish when the provider supplies fewer than two useful tags.
  for (final row in recipe.ingredients) {
    if (youtube || result.length >= 2) break;
    if (!const {
      'salt',
      'water',
      'oil',
      'pepper',
    }.contains(row.name.toLowerCase())) {
      add(row.name);
    }
  }
  if (result.length < 2) {
    final title = recipe.title.toLowerCase();
    for (final category in [
      'soup',
      'salad',
      'stew',
      'curry',
      'sandwich',
      'tacos',
      'pasta',
      'bread',
      'cake',
      'rice',
      'roast',
      'baked',
      'grilled',
      'marinated',
    ]) {
      if (RegExp('\\b$category\\b').hasMatch(title)) add(category);
      if (result.length >= 2) break;
    }
    if (!youtube && result.length < 2) add(recipe.title);
  }
  return result.values.toList();
}
