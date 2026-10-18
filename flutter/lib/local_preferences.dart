import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

enum SearchField { title, ingredients, tags, notes, description }

enum RecipeSort { edited, added, title }

enum RecipeView { cards, compact }

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
  ThemeMode themeMode = ThemeMode.system;
  bool wallpaperColors = false;
  bool shoppingKeepAwake = false;
  bool useAiForLink = false;
  bool saveImportPhotos = false;
  RecipeTextSize recipeTextSize = RecipeTextSize.normal;
  final Map<String, int> _steps = {};
  final Map<String, Set<int>> _checks = {};

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
      result.saveImportPhotos = map['saveImportPhotos'] == true;
      result.recipeTextSize =
          RecipeTextSize.values
              .where((v) => v.name == map['recipeTextSize'])
              .firstOrNull ??
          RecipeTextSize.normal;
      final offset = map['scrollOffset'];
      if (offset is num && offset.isFinite && offset >= 0) {
        result.scrollOffset = offset.toDouble();
      }
      if (map['steps'] is Map) {
        for (final entry in (map['steps'] as Map).entries) {
          if (entry.key is String && entry.value is int && entry.value >= 0) {
            result._steps[entry.key] = entry.value;
          }
        }
      }
      if (map['checks'] is Map) {
        for (final entry in (map['checks'] as Map).entries) {
          if (entry.key is String && entry.value is List) {
            result._checks[entry.key] = (entry.value as List)
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
    _changed();
  }

  int cookStep(String id) => _steps[id] ?? 0;
  Set<int> cookChecks(String id) => Set.of(_checks[id] ?? {});
  void saveCook(String id, int step, Set<int> checks) {
    _steps[id] = step;
    _checks[id] = Set.of(checks);
    _scheduleWrite();
  }

  void _changed() {
    _scheduleWrite();
    notifyListeners();
  }

  void _scheduleWrite() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 180), flush);
  }

  Future<void> flush() {
    _timer?.cancel();
    if (_path == null) return Future.value();
    final contents = jsonEncode({
      'query': query,
      'fields': searchFields.map((f) => f.name).toList(),
      'sort': sort.name,
      'view': view.name,
      'favoritesOnly': favoritesOnly,
      'scrollOffset': scrollOffset,
      'themeMode': themeMode.name,
      'wallpaperColors': wallpaperColors,
      'shoppingKeepAwake': shoppingKeepAwake,
      'useAiForLink': useAiForLink,
      'saveImportPhotos': saveImportPhotos,
      'recipeTextSize': recipeTextSize.name,
      'steps': _steps,
      'checks': _checks.map((key, value) => MapEntry(key, value.toList())),
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
