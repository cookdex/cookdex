import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import 'create_preferences.dart';

enum SearchField { title, ingredients, tags, notes, description }

enum RecipeSort { edited, added, title }

enum RecipeView { cards, compact }

enum YoutubeWatchModel {
  flash('gemini-3.8-flash'),
  followImport(null),
  lite('gemini-3.5-flash-lite');

  const YoutubeWatchModel(this.modelId);
  final String? modelId;
}

enum RecipeTextSize {
  normal('Default', 1),
  large('Large', 1.15),
  extraLarge('Extra large', 1.3);

  const RecipeTextSize(this.label, this.factor);
  final String label;
  final double factor;
}

/// Fresh Flutter preferences. The caller supplies only its own private path.
class LocalPreferences extends ChangeNotifier {
  LocalPreferences.memory() : _path = null;
  LocalPreferences._(this._path);

  final String? _path;
  Timer? _timer;
  Future<void> _writes = Future.value();
  String? persistenceError;
  String query = '';
  Set<SearchField> searchFields = Set.of(defaultSearchFields);
  RecipeSort sort = RecipeSort.edited;
  RecipeView view = RecipeView.cards;
  bool favoritesOnly = false;
  double scrollOffset = 0;
  double _beforeSearch = 0;
  final _recentRecipeOffsets = <String, Map<String, double>>{};
  ThemeMode themeMode = ThemeMode.system;
  bool wallpaperColors = false;
  bool shoppingKeepAwake = false;
  bool useAiForLink = false;
  YoutubeWatchModel youtubeWatchModel = YoutubeWatchModel.flash;
  bool saveImportPhotos = false;
  CreatePreferences _createPreferences = const CreatePreferences.defaults();
  CreatePreferences get createPreferences => _createPreferences;

  void setCreatePreferences(CreatePreferences value) {
    _createPreferences = value;
    _changed();
  }

  bool checkUpdatesAutomatically = false;
  String? dismissedUpdateVersion;
  int? lastUpdateCheckMs;
  RecipeTextSize recipeTextSize = RecipeTextSize.normal;
  final Map<String, List<List<String>>> _keptSeparate = {};
  List<List<String>> keptSeparate(String kind) => List.unmodifiable(
    (_keptSeparate[kind] ?? []).map(
      (names) => List<String>.unmodifiable(names),
    ),
  );
  void keepSeparate(String kind, Iterable<String> spellings) {
    final names = spellings.toSet().toList()..sort();
    if (names.length < 2) return;
    final groups = _keptSeparate.putIfAbsent(kind, () => []);
    if (groups.any((g) => listEquals(g, names))) return;
    groups.add(names);
    _changed();
  }

  void showTogether(String kind, Iterable<String> spellings) {
    final names = spellings.toSet().toList()..sort();
    _keptSeparate[kind]?.removeWhere((g) => listEquals(g, names));
    _changed();
  }

  bool isKeptSeparate(String kind, Iterable<String> spellings) =>
      (_keptSeparate[kind] ?? []).any((g) => spellings.every(g.contains));

  // Earlier versions can still read their saved progress after a downgrade.
  final Map<String, int> _legacySteps = {};
  final Map<String, Set<int>> _legacyChecks = {};
  final Map<String, int> _sessionSteps = {};
  final Map<String, Set<int>> _sessionChecks = {};

  static const defaultSearchFields = {
    SearchField.title,
    SearchField.ingredients,
    SearchField.tags,
  };

  static Future<LocalPreferences> load(String path) async {
    final result = LocalPreferences._(path);
    final file = File(path);
    if (!await file.exists()) return result;
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      result.query = map['query'] is String ? map['query'] as String : '';
      final kept = map['keptSeparate'];
      if (kept is Map) {
        for (final kind in ['ingredients', 'tags']) {
          final groups = kept[kind];
          if (groups is List) {
            result._keptSeparate[kind] = [
              for (final group in groups)
                if (group is List &&
                    group.length >= 2 &&
                    group.every((v) => v is String))
                  (group.cast<String>().toSet().toList()..sort()),
            ];
          }
        }
      }
      final fields = map['fields'];
      if (fields is List) {
        result.searchFields = SearchField.values
            .where((f) => fields.contains(f.name))
            .toSet();
      }
      result.sort =
          RecipeSort.values.where((v) => v.name == map['sort']).firstOrNull ??
          RecipeSort.edited;
      result.view =
          RecipeView.values.where((v) => v.name == map['view']).firstOrNull ??
          RecipeView.cards;
      result.favoritesOnly = map['favoritesOnly'] == true;
      result.themeMode =
          ThemeMode.values
              .where((mode) => mode.name == map['themeMode'])
              .firstOrNull ??
          ThemeMode.system;
      result.wallpaperColors = map['wallpaperColors'] == true;
      result.shoppingKeepAwake = map['shoppingKeepAwake'] == true;
      result.useAiForLink = map['useAiForLink'] == true;
      result.youtubeWatchModel = YoutubeWatchModel.values.firstWhere(
        (choice) => choice.name == map['youtubeWatchModel'],
        orElse: () => YoutubeWatchModel.flash,
      );
      result._createPreferences = CreatePreferences.fromJson(
        map['smartCreate'],
      );
      result.saveImportPhotos = map['saveImportPhotos'] == true;
      result.checkUpdatesAutomatically =
          map['checkUpdatesAutomatically'] == true;
      result.dismissedUpdateVersion = map['dismissedUpdateVersion'] is String
          ? map['dismissedUpdateVersion'] as String
          : null;
      final lastCheck = map['lastUpdateCheckMs'];
      result.lastUpdateCheckMs = lastCheck is int && lastCheck >= 0
          ? lastCheck
          : null;
      result.recipeTextSize =
          RecipeTextSize.values
              .where((v) => v.name == map['recipeTextSize'])
              .firstOrNull ??
          RecipeTextSize.normal;
      final offset = map['scrollOffset'];
      if (offset is num && offset.isFinite && offset >= 0) {
        result.scrollOffset = offset.toDouble();
      }
      final beforeSearch = map['beforeSearch'];
      if (beforeSearch is num && beforeSearch.isFinite && beforeSearch >= 0) {
        result._beforeSearch = beforeSearch.toDouble();
      }
      final recent = map['recentRecipeOffsets'];
      if (recent is List) {
        for (final panes in recent.take(2)) {
          if (panes is Map && panes['id'] is String) {
            result._recentRecipeOffsets[panes['id'] as String] = {
              for (final pane in ['recipe', 'overview', 'directions'])
                if (panes[pane] case final num value
                    when value.isFinite && value >= 0)
                  pane: value.toDouble(),
            };
          }
        }
      }
      if (map['steps'] is Map) {
        for (final entry in (map['steps'] as Map).entries) {
          if (entry.key is String && entry.value is int && entry.value >= 0) {
            result._legacySteps[entry.key] = entry.value;
          }
        }
      }
      if (map['checks'] is Map) {
        for (final entry in (map['checks'] as Map).entries) {
          if (entry.key is String && entry.value is List) {
            result._legacyChecks[entry.key] = (entry.value as List)
                .whereType<int>()
                .where((v) => v >= 0)
                .toSet();
          }
        }
      }
    } catch (_) {
      // Damaged local presentation preferences must not prevent recipe access.
      result.persistenceError = 'Local preferences could not be read.';
    }
    return result;
  }

  void setQuery(String value) {
    if (query == value) return;
    if (query.trim() != value.trim()) {
      if (query.trim().isEmpty) _beforeSearch = scrollOffset;
      scrollOffset = value.trim().isEmpty ? _beforeSearch : 0;
    }
    query = value;
    _changed();
  }

  void setSearchFields(Set<SearchField> value) {
    searchFields = Set.of(value);
    _changed();
  }

  void setSort(RecipeSort value) {
    sort = value;
    _changed();
  }

  void setView(RecipeView value) {
    view = value;
    _changed();
  }

  void setFavoritesOnly(bool value) {
    favoritesOnly = value;
    _changed();
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    _changed();
  }

  void setWallpaperColors(bool value) {
    wallpaperColors = value;
    _changed();
  }

  void setShoppingKeepAwake(bool value) {
    shoppingKeepAwake = value;
    _changed();
  }

  void setSaveImportPhotos(bool value) {
    saveImportPhotos = value;
    _changed();
  }

  void setCheckUpdatesAutomatically(bool value) {
    checkUpdatesAutomatically = value;
    _changed();
  }

  void recordUpdateCheck(int utcMilliseconds) {
    lastUpdateCheckMs = utcMilliseconds;
    _scheduleWrite();
  }

  void dismissUpdate(String version) {
    dismissedUpdateVersion = version;
    _scheduleWrite();
  }

  void setYoutubeWatchModel(YoutubeWatchModel choice) {
    youtubeWatchModel = choice;
    _changed();
  }

  void setUseAiForLink(bool value) {
    useAiForLink = value;
    _changed();
  }

  void setRecipeTextSize(RecipeTextSize value) {
    recipeTextSize = value;
    _changed();
  }

  void setScrollOffset(double value) {
    if (!value.isFinite) return;
    scrollOffset = value.clamp(0, double.infinity);
    _scheduleWrite();
  }

  void resetSearch() {
    query = '';
    searchFields = Set.of(defaultSearchFields);
    favoritesOnly = false;
    sort = RecipeSort.edited;
    view = RecipeView.cards;
    scrollOffset = 0;
    _beforeSearch = 0;
    _changed();
  }

  Map<String, double> openRecipeReadingOffsets(String id) {
    final offsets = _recentRecipeOffsets.remove(id) ?? <String, double>{};
    _recentRecipeOffsets[id] = offsets;
    if (_recentRecipeOffsets.length > 2) {
      _recentRecipeOffsets.remove(_recentRecipeOffsets.keys.first);
    }
    _scheduleWrite();
    return Map.of(offsets);
  }

  void saveRecipeReadingOffsets(String id, Map<String, double> panes) {
    final offsets = _recentRecipeOffsets[id];
    if (offsets == null ||
        panes.entries.every((p) => (offsets[p.key] ?? 0) == p.value)) {
      return;
    }
    for (final entry in panes.entries) {
      if (entry.value.isFinite) {
        offsets[entry.key] = entry.value.clamp(0, double.infinity);
      }
    }
    _scheduleWrite();
  }

  bool hasCookStep(String id) => _sessionSteps.containsKey(id);
  int cookStep(String id) => _sessionSteps[id] ?? 0;
  Set<int> cookChecks(String id) => Set.of(_sessionChecks[id] ?? {});
  void saveCook(String id, int step, Set<int> checks) {
    _sessionSteps[id] = step;
    _sessionChecks[id] = Set.of(checks);
  }

  void _changed() {
    _scheduleWrite();
    notifyListeners();
  }

  void _scheduleWrite() {
    if (_path == null) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 180), flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    if (_path == null) return Future.value();
    final contents = jsonEncode({
      'query': query,
      'keptSeparate': _keptSeparate,
      'fields': searchFields.map((f) => f.name).toList(),
      'sort': sort.name,
      'view': view.name,
      'favoritesOnly': favoritesOnly,
      'scrollOffset': scrollOffset,
      if (query.trim().isNotEmpty) 'beforeSearch': _beforeSearch,
      'recentRecipeOffsets': [
        for (final entry in _recentRecipeOffsets.entries)
          {'id': entry.key, ...entry.value},
      ],
      'themeMode': themeMode.name,
      'wallpaperColors': wallpaperColors,
      'shoppingKeepAwake': shoppingKeepAwake,
      'useAiForLink': useAiForLink,
      'youtubeWatchModel': youtubeWatchModel.name,
      'saveImportPhotos': saveImportPhotos,
      'smartCreate': createPreferences.toJson(),
      'checkUpdatesAutomatically': checkUpdatesAutomatically,
      'dismissedUpdateVersion': dismissedUpdateVersion,
      'lastUpdateCheckMs': lastUpdateCheckMs,
      'recipeTextSize': recipeTextSize.name,
      'steps': _legacySteps,
      'checks': _legacyChecks.map(
        (key, value) => MapEntry(key, value.toList()),
      ),
    });
    _writes = _writes.then((_) async {
      try {
        final file = File(_path);
        await file.parent.create(recursive: true);
        final temporary = File('$_path.tmp');
        await temporary.writeAsString(contents, flush: true);
        await temporary.rename(_path);
        persistenceError = null;
      } catch (_) {
        persistenceError = 'Local preferences could not be saved.';
      }
    });
    return _writes;
  }

  @override
  void dispose() {
    unawaited(flush());
    super.dispose();
  }
}
