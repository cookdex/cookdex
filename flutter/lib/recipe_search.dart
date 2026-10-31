import 'local_preferences.dart';
import 'src/rust/api.dart';

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

class RecipeSearchResult {
  const RecipeSearchResult(this.recipes, this.partialStart);

  final List<RecipeSummary> recipes;

  /// Present only when both full and partial matches exist.
  final int? partialStart;
}

/// Runtime-only ranking of cached, lowercase literal substring projections.
/// [ordered] supplies the existing selected sort, including its stable ID tie.
RecipeSearchResult rankRecipes(
  List<RecipeSummary> ordered,
  Map<String, Map<SearchField, String>> projections, {
  required String query,
  required Set<SearchField> fields,
  required bool favoritesOnly,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toSet();
  final terms = words.where((word) => !_fillerWords.contains(word)).toList();
  final filtered = ordered.where((r) => !favoritesOnly || r.favorite);
  // Empty and filler-only queries retain the former all-word inclusion/order.
  if (terms.isEmpty) {
    return RecipeSearchResult(
      List.unmodifiable(
        filtered.where(
          (r) => words.every(
            (word) => fields.any(
              (field) => projections[r.id]![field]!.contains(word),
            ),
          ),
        ),
      ),
      null,
    );
  }
  final matches =
      <({RecipeSummary recipe, int count, int weight, int order})>[];
  var order = 0;
  var full = 0;
  for (final recipe in filtered) {
    var count = 0;
    var weight = 0;
    final projection = projections[recipe.id]!;
    for (final term in terms) {
      var best = 0;
      for (final field in fields) {
        if (!projection[field]!.contains(term)) continue;
        final value = switch (field) {
          SearchField.title => 3,
          SearchField.tags || SearchField.ingredients => 2,
          SearchField.description || SearchField.notes => 1,
        };
        if (value > best) best = value;
      }
      if (best > 0) {
        count++;
        weight += best;
      }
    }
    if (count == terms.length) full++;
    if (count > 0) {
      matches.add((recipe: recipe, count: count, weight: weight, order: order));
    }
    order++;
  }
  matches.sort((a, b) {
    final count = b.count.compareTo(a.count);
    if (count != 0) return count;
    final weight = b.weight.compareTo(a.weight);
    return weight != 0 ? weight : a.order.compareTo(b.order);
  });
  return RecipeSearchResult(
    List.unmodifiable(matches.map((match) => match.recipe)),
    full > 0 && full < matches.length ? full : null,
  );
}
