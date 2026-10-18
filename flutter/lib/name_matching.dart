/// Whitespace cleanup for displayed names; spelling and punctuation are retained.
String normalizeNameWhitespace(String name) =>
    name.replaceAll(_whitespace, ' ').trim();

final _whitespace = RegExp(r'\s+', unicode: true);
final _dashes = RegExp(r'\p{Dash_Punctuation}+', unicode: true);
final _punctuation = RegExp(r'\p{Punctuation}', unicode: true);

/// A suggestion/guardrail key, never a replacement for a stored name.
///
/// Dashes act as word separators; other punctuation is ignored. Unicode
/// letters, accents, numbers and symbols remain meaningful. There is no
/// stemming, singularization, transliteration or automatic spelling change.
String sameNameKey(String name) => normalizeNameWhitespace(
  name.toLowerCase().replaceAll(_dashes, ' ').replaceAll(_punctuation, ''),
);

class NameObservation {
  const NameObservation({
    required this.name,
    required this.recipeId,
    required this.updatedAt,
  });

  final String name;
  final String recipeId;
  final String updatedAt;
}

class NameSuggestion {
  const NameSuggestion({
    required this.key,
    required this.name,
    required this.recipeCount,
    required this.latestUpdatedAt,
  });

  final String key;
  final String name;

  /// Distinct recipes using any spelling in this group.
  final int recipeCount;
  final String latestUpdatedAt;
}

/// Groups observations without changing their source recipes.
///
/// The preferred whitespace-normalized spelling is the one used by the most
/// distinct recipes, then the most recently updated recipe. Exact lexical
/// spelling resolves remaining ties independently of input order. Empty keys
/// are omitted; suggestions are sorted by distinct recipe count, then recency,
/// then key for stable display.
List<NameSuggestion> groupNameSuggestions(
  Iterable<NameObservation> observations,
) {
  final groups = <String, Map<String, _NameUsage>>{};
  for (final observation in observations) {
    final name = normalizeNameWhitespace(observation.name);
    final key = sameNameKey(name);
    if (key.isEmpty) continue;
    final spellings = groups.putIfAbsent(key, () => {});
    final usage = spellings.putIfAbsent(name, _NameUsage.new);
    usage.recipeIds.add(observation.recipeId);
    if (usage.latestUpdatedAt == null ||
        _preferTimestamp(observation.updatedAt, usage.latestUpdatedAt!)) {
      usage.latestUpdatedAt = observation.updatedAt;
    }
  }
  final suggestions = <NameSuggestion>[];
  for (final group in groups.entries) {
    final spellings = group.value.entries.toList()
      ..sort((a, b) {
        final count = b.value.recipeIds.length.compareTo(
          a.value.recipeIds.length,
        );
        if (count != 0) return count;
        final recency = _compareUpdatedAt(
          b.value.latestUpdatedAt!,
          a.value.latestUpdatedAt!,
        );
        return recency != 0 ? recency : a.key.compareTo(b.key);
      });
    final recipeIds = <String>{};
    var latest = spellings.first.value.latestUpdatedAt!;
    for (final spelling in spellings) {
      recipeIds.addAll(spelling.value.recipeIds);
      final updatedAt = spelling.value.latestUpdatedAt!;
      if (_preferTimestamp(updatedAt, latest)) latest = updatedAt;
    }
    suggestions.add(
      NameSuggestion(
        key: group.key,
        name: spellings.first.key,
        recipeCount: recipeIds.length,
        latestUpdatedAt: latest,
      ),
    );
  }
  suggestions.sort((a, b) {
    final count = b.recipeCount.compareTo(a.recipeCount);
    if (count != 0) return count;
    final recency = _compareUpdatedAt(b.latestUpdatedAt, a.latestUpdatedAt);
    return recency != 0 ? recency : a.key.compareTo(b.key);
  });
  return suggestions;
}

class _NameUsage {
  final recipeIds = <String>{};
  String? latestUpdatedAt;
}

bool _preferTimestamp(String candidate, String current) {
  final recency = _compareUpdatedAt(candidate, current);
  return recency > 0 || (recency == 0 && candidate.compareTo(current) < 0);
}

int _compareUpdatedAt(String a, String b) {
  final aTime = DateTime.tryParse(a);
  final bTime = DateTime.tryParse(b);
  if (aTime != null && bTime != null) return aTime.compareTo(bTime);
  if (aTime != null) return 1;
  if (bTime != null) return -1;
  return a.compareTo(b);
}
