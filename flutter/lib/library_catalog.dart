import 'dart:isolate';

import 'name_matching.dart';
import 'name_spelling.dart';
import 'src/rust/api.dart';

enum LibraryKind { ingredients, tags }

class LibraryName {
  LibraryName(this.name, this.recipes);
  final String name;
  final List<RecipeSummary> recipes;
  int get count => recipes.length;
  String get letter {
    final first = String.fromCharCode(name.trimLeft().runes.first)
        .toUpperCase();
    return RegExp(r'^\p{Letter}$', unicode: true).hasMatch(first) ? first : '#';
  }
}

class LibraryCatalog {
  LibraryCatalog(List<RecipeSummary> recipes, LibraryKind kind) {
    final byName = <String, List<RecipeSummary>>{};
    for (final recipe in recipes) {
      for (final name
          in (kind == LibraryKind.tags ? recipe.tags : recipe.ingredients)
              .toSet()) {
        if (name.trim().isEmpty) continue;
        byName.putIfAbsent(name, () => []).add(recipe);
      }
    }
    names = [
      for (final entry in byName.entries)
        LibraryName(
          entry.key,
          entry.value..sort((a, b) => compareNames(a.title, b.title)),
        ),
    ]..sort((a, b) => compareNames(a.name, b.name));
  }
  late final List<LibraryName> names;
  // Name lookup does not need fuzzy groups. Build once, only on first display.
  late final List<List<LibraryName>> duplicates = _duplicateGroups();
  List<List<LibraryName>> _duplicateGroups() => _resolveGroups(
    _findDuplicateNames([for (final n in names) (n.name, n.count)]),
  );
  List<List<LibraryName>> _resolveGroups(List<List<String>> groups) {
    final byName = {for (final n in names) n.name: n};
    return [
      for (final group in groups) [for (final name in group) byName[name]!],
    ];
  }

  Future<List<List<LibraryName>>> loadDuplicates() async {
    if (names.length <= 160) return duplicates;
    return _resolveGroups(
      await _findDuplicatesOffThread([
        for (final n in names) (n.name, n.count),
      ]),
    );
  }

  LibraryName? named(String name) =>
      names.where((n) => n.name == name).firstOrNull;
  LibraryName? matchingTag(String value) {
    final exact = named(value);
    final key = sameNameKey(value);
    if (exact != null || key.isEmpty) return exact;
    final matches = names.where((n) => sameNameKey(n.name) == key).toList()
      ..sort(compareLibraryUsage);
    return matches.firstOrNull;
  }

  LibraryName? matching(String name, String excluding) =>
      names.where((n) => n.name != excluding && n.name == name).firstOrNull ??
      names
          .where(
            (n) =>
                n.name != excluding &&
                sameNameKey(name).isNotEmpty &&
                sameNameKey(n.name) == sameNameKey(name),
          )
          .firstOrNull;
}

int compareNames(String a, String b) {
  final order = a.toLowerCase().compareTo(b.toLowerCase());
  return order == 0 ? a.compareTo(b) : order;
}

bool singularPluralLibraryNames(String a, String b) =>
    singularPluralNames(a, b);

String? libraryNumberWarning(List<String> sources, String target) {
  final source = sources
      .where((s) => singularPluralLibraryNames(s, target))
      .firstOrNull;
  if (source == null) return null;
  final quantity = pluralNameOf(source, target) ? '1' : '2';
  return '“$source” and “$target” are singular and plural forms. Some lines may read oddly afterward, for example “$quantity $target”.';
}

bool similarLibraryName(String a, String b) =>
    NameSpelling(a).sameOrSimilar(NameSpelling(b)) || singularPluralNames(a, b);

String recipeCount(int count) => '$count ${count == 1 ? 'recipe' : 'recipes'}';

int compareLibraryUsage(LibraryName a, LibraryName b) {
  final count = b.count.compareTo(a.count);
  if (count != 0) return count;
  final marks = _namePunctuation
      .allMatches(a.name)
      .length
      .compareTo(_namePunctuation.allMatches(b.name).length);
  if (marks != 0) return marks;
  final aLower = a.name == a.name.toLowerCase();
  final bLower = b.name == b.name.toLowerCase();
  if (aLower != bLower) return aLower ? -1 : 1;
  return compareNames(a.name, b.name);
}

final _namePunctuation = RegExp(r'\p{Punctuation}', unicode: true);

bool hasSimilarSpelling(List<LibraryName> group) =>
    group.any((n) => sameNameKey(n.name) != sameNameKey(group.first.name));

class _CountedLibraryName extends LibraryName {
  _CountedLibraryName(String name, this.usage) : super(name, const []);
  final int usage;
  @override
  int get count => usage;
}

Future<List<List<String>>> _findDuplicatesOffThread(
  List<(String, int)> values,
) => Isolate.run(() => _findDuplicateNames(values));
List<List<String>> _findDuplicateNames(List<(String, int)> values) {
  final preferred = [
    for (final (name, count) in values) _CountedLibraryName(name, count),
  ]..sort(compareLibraryUsage);
  final spellings = {for (final n in preferred) n: NameSpelling(n.name)};
  final byLength = <int, List<LibraryName>>{};
  for (final n in preferred) {
    byLength.putIfAbsent(spellings[n]!.runes.length, () => []).add(n);
  }
  final assigned = <LibraryName>{};
  final groups = <List<LibraryName>>[];
  for (final anchor in preferred) {
    if (!assigned.add(anchor)) continue;
    final spelling = spellings[anchor]!;
    final group = <LibraryName>[anchor];
    for (
      var length = spelling.runes.length - 2;
      length <= spelling.runes.length + 2;
      length++
    ) {
      for (final candidate in byLength[length] ?? <LibraryName>[]) {
        if (!assigned.contains(candidate) &&
            spelling.sameOrSimilar(spellings[candidate]!)) {
          group.add(candidate);
          assigned.add(candidate);
        }
      }
    }
    if (group.length > 1) groups.add(group..sort(compareLibraryUsage));
  }
  groups.sort((a, b) => compareNames(a.first.name, b.first.name));
  return [
    for (final group in groups) [for (final n in group) n.name],
  ];
}
