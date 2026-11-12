import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_preferences.dart';
import 'name_matching.dart';
import 'recipe_search.dart';
import 'src/rust/api.dart' as core;

class BackupPreview {
  const BackupPreview(this.report, this.token);
  final core.RestoreReport report;
  final Object token;
}

class LibraryChangeResult {
  const LibraryChangeResult(this.snapshot, this.undo, this.count);
  final core.CollectionSnapshot snapshot;
  final Object undo;
  final int count;
}

abstract interface class LibraryRepository {
  Future<LibraryChangeResult> addLibraryTag(
    int generation,
    List<String> ids,
    String tag,
  );
  Future<LibraryChangeResult> changeLibraryNames(
    int generation,
    bool tags,
    List<String> sources,
    String? target,
  );
  Future<core.CollectionSnapshot> undoLibraryNames(int generation, Object undo);
}

abstract interface class RecipeRepository {
  Future<core.CollectionSnapshot> snapshot();
  Stream<core.CollectionEvent> subscribe();
  Future<core.Recipe?> detail(String id);
  Future<List<String>> ingredientAmounts(List<core.Ingredient> ingredients);
  Future<core.CollectionSnapshot> favorite(
    int generation,
    String id,
    bool value,
  );
  Future<core.CollectionSnapshot> delete(int generation, String id);
  Future<BackupPreview> previewRestore(Uint8List bytes);
  Future<core.CollectionSnapshot> restore(BackupPreview preview);
  Future<void> close();
}

/// Its subscription begins with a snapshot registered atomically with changes.
/// Repositories without this guarantee still use an explicit initial refresh.
abstract interface class SnapshotSubscriptionRepository
    implements RecipeRepository {}

abstract interface class SetAsideRepository {
  Future<core.CollectionSnapshot> discardSetAside(int generation);
}

abstract interface class BatchDeleteRepository {
  Future<core.CollectionSnapshot> deleteMany(int generation, List<String> ids);
}

/// Editor operations remain typed; only Rust normalizes recipe input.
abstract interface class EditorRecipeRepository {
  Future<core.RecipeFields> normalizeEditorFields(
    core.RecipeFields fields,
    List<String?> amountInputs,
  );
  Future<List<core.PastedIngredient>> parseIngredientPaste(
    String text,
    String section,
  );
  Future<core.CollectionSnapshot> save(
    int generation,
    core.Recipe? base,
    core.RecipeFields fields,
  );
}

abstract interface class ImportRecipeRepository {
  Future<core.CollectionSnapshot> importOne(
    int generation,
    core.RecipeFields fields,
    core.DuplicateChoice? choice,
  );
}

abstract interface class ShoppingRepository {
  Future<core.ShoppingResult> addShopping(
    int generation,
    String id,
    List<int> indices,
  );
  Future<core.ShoppingResult> editShopping(
    int generation,
    core.ShoppingEdit edit,
  );
  Future<core.CollectionSnapshot> undoShopping(
    int generation,
    core.ShoppingUndo undo,
  );
}

abstract interface class ScalingRepository {
  Future<core.ScaledRecipeView> scaleRecipe(
    core.RecipeFields fields,
    int scale,
  );
  Future<core.ShoppingResult> addShoppingScaled(
    int generation,
    String id,
    List<int> indices,
    int scale,
  );
}

/// All recipe operations cross the generated typed bridge; no JSON book mirror.
class RustRecipeRepository
    implements
        RecipeRepository,
        SnapshotSubscriptionRepository,
        EditorRecipeRepository,
        ShoppingRepository,
        ImportRecipeRepository,
        SetAsideRepository,
        BatchDeleteRepository,
        LibraryRepository,
        ScalingRepository {
  RustRecipeRepository(this.session);
  final core.CoreSession session;
  @override
  Future<LibraryChangeResult> addLibraryTag(
    int generation,
    List<String> ids,
    String tag,
  ) async {
    final result = await session.addLibraryTag(
      generation: generation,
      ids: ids,
      tag: tag,
      operation: core.Operation(),
    );
    return LibraryChangeResult(result.snapshot, result.undo, result.count);
  }

  @override
  Future<LibraryChangeResult> changeLibraryNames(
    int generation,
    bool tags,
    List<String> sources,
    String? target,
  ) async {
    final result = await session.changeLibraryNames(
      generation: generation,
      tags: tags,
      sources: sources,
      target: target,
      operation: core.Operation(),
    );
    return LibraryChangeResult(result.snapshot, result.undo, result.count);
  }

  @override
  Future<core.CollectionSnapshot> undoLibraryNames(
    int generation,
    Object undo,
  ) => session.undoLibraryNames(
    generation: generation,
    undo: undo as core.LibraryUndo,
    operation: core.Operation(),
  );
  @override
  Future<core.CollectionSnapshot> deleteMany(
    int generation,
    List<String> ids,
  ) => session.deleteMany(
    generation: generation,
    ids: ids,
    operation: core.Operation(),
  );
  @override
  Future<core.CollectionSnapshot> discardSetAside(int generation) => session
      .discardSetAside(generation: generation, operation: core.Operation());
  @override
  Future<core.ShoppingResult> addShopping(
    int generation,
    String id,
    List<int> indices,
  ) => session.addShopping(
    generation: generation,
    id: id,
    indices: indices,
    operation: core.Operation(),
  );
  @override
  Future<core.ShoppingResult> editShopping(
    int generation,
    core.ShoppingEdit edit,
  ) => session.editShopping(
    generation: generation,
    edit: edit,
    operation: core.Operation(),
  );
  @override
  Future<core.CollectionSnapshot> undoShopping(
    int generation,
    core.ShoppingUndo undo,
  ) => session.undoShopping(
    generation: generation,
    undo: undo,
    operation: core.Operation(),
  );
  @override
  Future<core.ScaledRecipeView> scaleRecipe(
    core.RecipeFields fields,
    int scale,
  ) => core.scaleRecipeView(fields: fields, scale: scale);
  @override
  Future<core.ShoppingResult> addShoppingScaled(
    int generation,
    String id,
    List<int> indices,
    int scale,
  ) => session.addShoppingScaled(
    generation: generation,
    id: id,
    indices: indices,
    scale: scale,
    operation: core.Operation(),
  );
  core.Operation? _subscriptionOperation;
  @override
  Future<core.CollectionSnapshot> snapshot() => session.snapshot();
  @override
  Future<core.CollectionSnapshot> importOne(
    int generation,
    core.RecipeFields fields,
    core.DuplicateChoice? choice,
  ) => session.importOne(
    generation: generation,
    fields: fields,
    choice: choice,
    operation: core.Operation(),
  );
  @override
  Stream<core.CollectionEvent> subscribe() {
    _subscriptionOperation?.cancel();
    _subscriptionOperation = core.Operation();
    return core.subscribe(session: session, operation: _subscriptionOperation!);
  }

  @override
  Future<core.Recipe?> detail(String id) => session.detail(id: id);
  @override
  Future<List<String>> ingredientAmounts(List<core.Ingredient> ingredients) =>
      core.formatIngredientAmounts(ingredients: ingredients);
  @override
  Future<core.RecipeFields> normalizeEditorFields(
    core.RecipeFields fields,
    List<String?> amountInputs,
  ) => core.parseEditorFields(fields: fields, amountInputs: amountInputs);
  @override
  Future<List<core.PastedIngredient>> parseIngredientPaste(
    String text,
    String section,
  ) => core.parseIngredientPaste(text: text, section: section);
  @override
  Future<core.CollectionSnapshot> save(
    int generation,
    core.Recipe? base,
    core.RecipeFields fields,
  ) => session.save(
    generation: generation,
    base: base,
    fields: fields,
    operation: core.Operation(),
  );
  @override
  Future<core.CollectionSnapshot> favorite(
    int generation,
    String id,
    bool value,
  ) => session.favorite(
    generation: generation,
    id: id,
    value: value,
    operation: core.Operation(),
  );
  @override
  Future<core.CollectionSnapshot> delete(int generation, String id) => session
      .delete(generation: generation, id: id, operation: core.Operation());
  @override
  Future<BackupPreview> previewRestore(Uint8List bytes) async {
    final preview = await session.previewRestore(
      bytes: bytes,
      operation: core.Operation(),
    );
    return BackupPreview(await preview.report(), preview);
  }

  @override
  Future<core.CollectionSnapshot> restore(BackupPreview preview) =>
      session.restore(
        preview: preview.token as core.RestorePreview,
        operation: core.Operation(),
      );
  @override
  Future<void> close() async {
    _subscriptionOperation?.cancel();
    await session.close();
  }
}

class FavoriteUndo {
  const FavoriteUndo({
    required this.id,
    required this.before,
    required this.after,
    required this.revision,
  });
  final String id;
  final bool before, after;
  final int revision;
}

class RecipeStore extends ChangeNotifier {
  RecipeStore(this.repository, this.preferences) {
    preferences.addListener(_preferencesChanged);
  }
  final RecipeRepository repository;
  final LocalPreferences preferences;
  int generation = -1;
  int _observedGeneration = -1;
  int get syncGeneration =>
      _observedGeneration > generation ? _observedGeneration : generation;
  bool loading = true;
  String? error;
  bool _disposed = false;
  core.CollectionSnapshot? _snapshot;
  final Map<String, core.Recipe> _details = {};
  final Map<String, List<String>> _amounts = {};
  RecipeSearchIndex? _search;
  bool _waitingForFirstIndex = false;
  bool get preparingRecipeSearch =>
      _waitingForFirstIndex &&
      preferences.query.trim().isNotEmpty &&
      summaries.isNotEmpty;
  final _sortTitles = <String, String>{};
  final Map<RecipeSort, List<core.RecipeSummary>> _ordered = {};
  List<core.RecipeSummary>? _visible;
  int _fullMatchCount = 0;
  int get fullMatchCount => _fullMatchCount;
  int? get partialMatchStart =>
      _fullMatchCount < visibleRecipes.length
      ? _fullMatchCount
      : null;
  String? _visibleQuery;
  RecipeSort? _visibleSort;
  Set<SearchField> _visibleFields = const {};
  bool? _visibleFavorites;
  List<String>? _editorIngredientNames;
  List<String>? _editorTags;
  List<String> _groupEditorNames(bool tags) => List.unmodifiable(
    groupNameSuggestions([
      for (final recipe in summaries)
        for (final name in tags ? recipe.tags : recipe.ingredients)
          NameObservation(
            name: name,
            recipeId: recipe.id,
            updatedAt: recipe.updatedAt,
          ),
    ]).map((suggestion) => suggestion.name),
  );
  List<String> get editorIngredientNames =>
      _editorIngredientNames ??= _groupEditorNames(false);
  List<String> get editorTags => _editorTags ??= _groupEditorNames(true);
  final Map<String, int> _versions = {};
  final Map<String, Future<core.Recipe?>> _pending = {};
  final Map<String, Future<List<String>>> _pendingAmounts = {};
  StreamSubscription<core.CollectionEvent>? _subscription;
  Completer<void>? _subscriptionReady;
  Timer? _reconnect;
  Future<void>? _refresh;
  bool _refreshAgain = false;
  Future<void> _mutations = Future.value();
  bool _writing = false;
  int _deferredGeneration = -1;
  final Map<String, List<({Object token, bool value})>> _favoriteWrites = {};
  List<core.RecipeSummary>? _optimisticSummaries;
  Map<String, core.RecipeSummary> _summariesById = const {};

  String? shoppingSourceLabel(core.ShoppingItem item) {
    if (item.contributorIds.isEmpty) return null;
    final names = [
      for (final id in item.contributorIds.toSet()) ?_summariesById[id]?.title,
    ];
    if (names.isEmpty) return null;
    final first = names.take(2).join(', ');
    return names.length <= 2 ? first : '$first +${names.length - 2} more';
  }

  List<core.RecipeSummary> get _savedSummaries =>
      _snapshot?.summaries ?? const [];
  List<core.RecipeSummary> get summaries =>
      _optimisticSummaries ?? _savedSummaries;
  bool isFavorite(String id) => _summary(id)?.favorite ?? false;

  void _projectFavorites() {
    if (_favoriteWrites.isEmpty && _optimisticSummaries == null) return;
    _optimisticSummaries = _favoriteWrites.isEmpty
        ? null
        : [
            for (final r in _savedSummaries)
              if (_favoriteWrites[r.id]?.lastOrNull case final pending?)
                core.RecipeSummary(
                  id: r.id,
                  title: r.title,
                  description: r.description,
                  ingredients: r.ingredients,
                  tags: r.tags,
                  notes: r.notes,
                  favorite: pending.value,
                  createdAt: r.createdAt,
                  updatedAt: r.updatedAt,
                  revision: r.revision,
                  servings: r.servings,
                  prepTime: r.prepTime,
                  cookTime: r.cookTime,
                  totalTime: r.totalTime,
                )
              else
                r,
          ];
    _ordered.clear();
    _visible = null;
    _refreshVisible();
  }

  List<core.ShoppingCategory> get shoppingCategories =>
      _snapshot?.shoppingCategories ?? const [];

  List<core.ShoppingItem> get shopping => _snapshot?.shopping ?? const [];
  List<core.Conflict> get conflicts => _snapshot?.conflicts ?? const [];
  int get setAsideCount => _snapshot?.setAsideCount ?? 0;
  Future<void> discardSetAside(int expectedGeneration) => _mutate(() async {
    _apply(
      await (repository as SetAsideRepository).discardSetAside(
        expectedGeneration,
      ),
    );
    error = null;
  });
  bool get hasPrevious => _snapshot?.hasPrevious ?? false;
  Future<core.ShoppingUndo> addShopping(
    String id,
    List<int> indices, {
    int scale = 2,
  }) => _mutate(() async {
    final result = repository is ScalingRepository
        ? await (repository as ScalingRepository).addShoppingScaled(
            generation,
            id,
            indices,
            scale,
          )
        : scale == 2
        ? await (repository as ShoppingRepository).addShopping(
            generation,
            id,
            indices,
          )
        : throw StateError('Recipe scaling is unavailable.');
    _apply(result.snapshot);
    error = null;
    return result.undo;
  });
  Future<core.ShoppingUndo> editShopping(core.ShoppingEdit edit) =>
      _mutate(() async {
        final result = await (repository as ShoppingRepository).editShopping(
          generation,
          edit,
        );
        _apply(result.snapshot);
        error = null;
        return result.undo;
      });
  Future<void> undoShopping(core.ShoppingUndo undo) => _mutate(() async {
    _apply(
      await (repository as ShoppingRepository).undoShopping(generation, undo),
    );
    error = null;
  });
  final _shoppingCount = ValueNotifier<int>(0);
  final _pendingChecks = <String, ({Object token, bool checked})>{};
  ValueListenable<int> get shoppingCount => _shoppingCount;
  int get uncheckedShoppingCount => _shoppingCount.value;

  void _updateShoppingCount() {
    if (_disposed) return;
    _shoppingCount.value = shopping
        .where((item) => !(_pendingChecks[item.id]?.checked ?? item.checked))
        .length;
  }

  Future<void> checkShoppingRow(String id, bool checked) async {
    final token = Object();
    _pendingChecks[id] = (token: token, checked: checked);
    _updateShoppingCount();
    try {
      await editShopping(core.ShoppingEdit.check(ids: [id], checked: checked));
    } finally {
      if (identical(_pendingChecks[id]?.token, token)) {
        _pendingChecks.remove(id);
        _updateShoppingCount();
      }
    }
  }

  /// Computed on query/filter/collection changes, never while building/scrolling.
  List<core.RecipeSummary> get visibleRecipes => _visible ?? const [];

  void _refreshVisible() {
    final sameOptions =
        _visible != null &&
        _visibleSort == preferences.sort &&
        _visibleFavorites == preferences.favoritesOnly &&
        setEquals(_visibleFields, preferences.searchFields);
    if (sameOptions && _visibleQuery == preferences.query) return;
    if (preparingRecipeSearch) {
      _visible = null;
      _fullMatchCount = 0;
      return;
    }
    final result = _rank(preferences, picker: false);
    _fullMatchCount = result.fullCount;
    if (!listEquals(result.recipes, _visible)) _visible = result.recipes;
    _visibleQuery = preferences.query;
    _visibleSort = preferences.sort;
    _visibleFields = Set.of(preferences.searchFields);
    _visibleFavorites = preferences.favoritesOnly;
  }

  List<core.RecipeSummary> _orderedRecipes(RecipeSort sort) =>
      _ordered.putIfAbsent(sort, () {
        final result = summaries.toList();
        result.sort((a, b) {
          final primary = switch (sort) {
            RecipeSort.edited => b.updatedAt.compareTo(a.updatedAt),
            RecipeSort.added => b.createdAt.compareTo(a.createdAt),
            RecipeSort.title =>
              _sortTitles
                  .putIfAbsent(a.id, a.title.toLowerCase)
                  .compareTo(
                    _sortTitles.putIfAbsent(b.id, b.title.toLowerCase),
                  ),
          };
          return primary == 0 ? a.id.compareTo(b.id) : primary;
        });
        return result;
      });

  RecipeSearchIndex _startSearchIndex() {
    final index = RecipeSearchIndex(() {
      if (!_waitingForFirstIndex || _disposed) return;
      _waitingForFirstIndex = false;
      if (preferences.query.trim().isNotEmpty) {
        _refreshVisible();
        notifyListeners();
      }
    });
    for (final r in _savedSummaries) {
      index.queue(r);
    }
    return index;
  }

  /// Called after the first Recipes frame. Searchable text is shared across
  /// rows and prepared in short event-loop slices while the library is idle.
  void prepareRecipeSearch() {
    if (_disposed) return;
    (_search ??= _startSearchIndex()).warm();
  }

  List<core.RecipeSummary> recipesMatching(LocalPreferences filters) =>
      _rank(filters, picker: true).recipes;

  RecipeSearchResult _rank(LocalPreferences filters, {required bool picker}) {
    final ordered = _orderedRecipes(filters.sort);
    if (filters.query.trim().isEmpty) {
      final rows = List<core.RecipeSummary>.unmodifiable(
        filters.favoritesOnly ? ordered.where((r) => r.favorite) : ordered,
      );
      return RecipeSearchResult(rows, rows.length);
    }
    if (ordered.isEmpty) return const RecipeSearchResult([], 0);
    return (_search ??= _startSearchIndex()).rank(
      ordered,
      filters,
      picker: picker,
    );
  }

  Future<void> initialize({bool prepareSearchAfterPaint = false}) async {
    _waitingForFirstIndex = prepareSearchAfterPaint;
    final ready = _listen();
    await (repository is SnapshotSubscriptionRepository ? ready : refresh());
  }

  Future<void> _listen() {
    if (_disposed) return Future.value();
    final ready = Completer<void>();
    var fallbackStarted = false;
    _subscriptionReady = ready;
    void complete() {
      if (!ready.isCompleted) ready.complete();
    }

    void lost(Object? error) {
      _connectionLost(error);
      // A failed initial subscription must still allow the ordinary snapshot
      // and Retry path. A successful subscription never needs that second read.
      if (!ready.isCompleted && !fallbackStarted) {
        fallbackStarted = true;
        unawaited(refresh().whenComplete(complete));
      }
    }

    try {
      _subscription = repository.subscribe().listen(
        (event) {
          if (_disposed) return;
          switch (event) {
            case core.CollectionEvent_Snapshot(:final field0):
              error = null;
              _apply(field0, external: true);
              complete();
            case core.CollectionEvent_Change(:final field0):
              if (field0.generation <= generation) return;
              _observedGeneration = field0.generation;
              notifyListeners();
              if (_writing) {
                if (field0.generation > _deferredGeneration) {
                  _deferredGeneration = field0.generation;
                }
                return;
              }
              for (final id in {...field0.changed, ...field0.deleted}) {
                _invalidate(id);
              }
              unawaited(refresh());
          }
        },
        onError: (Object e) => lost(e),
        onDone: () => lost(null),
      );
    } catch (e) {
      lost(e);
    }
    return ready.future;
  }

  void _connectionLost(Object? e) {
    if (_disposed || _reconnect != null) return;
    if (e != null) {
      error = _message(e);
      notifyListeners();
    }
    _reconnect = Timer(const Duration(seconds: 1), () async {
      _reconnect = null;
      await _subscription?.cancel();
      if (!_disposed) {
        await initialize();
      }
    });
  }

  Future<void> refresh() {
    if (_refresh != null) {
      _refreshAgain = true;
      return _refresh!;
    }
    final completer = Completer<void>();
    _refresh = completer.future;
    () async {
      try {
        do {
          _refreshAgain = false;
          final snapshot = await repository.snapshot();
          if (!_disposed) {
            _apply(snapshot, external: true);
            error = null;
          }
        } while (_refreshAgain && !_disposed);
      } catch (e) {
        if (!_disposed) error = _message(e);
      } finally {
        _refresh = null;
        if (!_disposed) {
          loading = false;
          notifyListeners();
        }
        completer.complete();
      }
    }();
    return completer.future;
  }

  core.RecipeSummary? _summary(String id) =>
      summaries.where((r) => r.id == id).firstOrNull;
  bool _sameSummary(core.RecipeSummary a, core.RecipeSummary b) =>
      a.id == b.id &&
      a.revision == b.revision &&
      a.title == b.title &&
      a.description == b.description &&
      listEquals(a.ingredients, b.ingredients) &&
      listEquals(a.tags, b.tags) &&
      a.notes == b.notes &&
      a.favorite == b.favorite &&
      a.createdAt == b.createdAt &&
      a.updatedAt == b.updatedAt &&
      a.servings == b.servings &&
      a.prepTime == b.prepTime &&
      a.cookTime == b.cookTime &&
      a.totalTime == b.totalTime;

  void _apply(
    core.CollectionSnapshot snapshot, {
    bool notify = true,
    bool external = false,
  }) {
    if (_disposed || snapshot.generation < generation) return;
    // Includes subscription reconnect snapshots: causal alternatives can share
    // summary metadata while changing quantities/steps. Invalidate pending loads
    // before advancing the observed generation, not just on explicit refresh.
    if (external && snapshot.generation > generation) {
      for (final id in summaries.map((r) => r.id).toList()) {
        _invalidate(id);
      }
    }
    final before = _summariesById;
    // FRB decodes a fresh object graph for every snapshot. Retain equal row
    // objects so visible rows can skip rebuilding after unrelated mutations.
    final stableSummaries = snapshot.summaries
        .map((r) {
          final previous = before[r.id];
          return previous != null && _sameSummary(previous, r) ? previous : r;
        })
        .toList(growable: false);
    final after = {for (final r in stableSummaries) r.id: r};
    _summariesById = after;
    if (!listEquals(stableSummaries, _savedSummaries)) {
      _ordered.clear();
      _visible = null;
      _editorIngredientNames = null;
      _editorTags = null;
    }
    for (final id in {...before.keys, ...after.keys}) {
      if (!identical(before[id], after[id])) {
        _invalidate(id);
        _sortTitles.remove(id);
        if (before[id] case final old?) _search?.remove(old);
        if (after[id] case final current?) _search?.queue(current);
      }
    }
    _snapshot = core.CollectionSnapshot(
      setAsideCount: snapshot.setAsideCount,
      generation: snapshot.generation,
      summaries: stableSummaries,
      shopping: snapshot.shopping,
      shoppingCategories: snapshot.shoppingCategories,
      conflicts: snapshot.conflicts,
      hasPrevious: snapshot.hasPrevious,
    );
    generation = snapshot.generation;
    _updateShoppingCount();
    _projectFavorites();
    _refreshVisible();
    loading = false;
    _search?.warm();
    if (notify) notifyListeners();
  }

  void _invalidate(String id) {
    _versions[id] = (_versions[id] ?? 0) + 1;
    _details.remove(id);
    _amounts.remove(id);
  }

  core.Recipe? cachedDetail(String id) => _details[id];
  Future<core.Recipe?> detail(String id) {
    if (_details.containsKey(id)) return Future.value(_details[id]);
    return _pending.putIfAbsent(
      id,
      () => _loadDetail(id).whenComplete(() {
        _pending.remove(id);
      }),
    );
  }

  Future<core.Recipe?> _loadDetail(String id) async {
    while (!_disposed) {
      if (_refresh != null) await _refresh;
      final version = _versions[id] ?? 0;
      if (_summary(id) == null) return null;
      final recipe = await repository.detail(id);
      if (version != (_versions[id] ?? 0)) continue;
      if (recipe != null) _details[id] = recipe;
      // Completion drives the requesting FutureBuilder. Publishing here would
      // recreate its future while Flutter is laying out recipe contents.
      return recipe;
    }
    return null;
  }

  Future<List<String>> ingredientAmounts(String id) {
    if (_amounts.containsKey(id)) return Future.value(_amounts[id]);
    return _pendingAmounts.putIfAbsent(
      id,
      () => _loadAmounts(id).whenComplete(() {
        _pendingAmounts.remove(id);
      }),
    );
  }

  Future<List<String>> _loadAmounts(String id) async {
    while (!_disposed) {
      final recipe = await detail(id);
      if (recipe == null) return [];
      final version = _versions[id] ?? 0;
      final amounts = await repository.ingredientAmounts(
        recipe.fields.ingredients,
      );
      if (version != (_versions[id] ?? 0)) continue;
      _amounts[id] = amounts;
      return amounts;
    }
    return [];
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _mutations = _mutations.then((_) async {
      _writing = true;
      try {
        completer.complete(await action());
      } catch (e, stack) {
        if (!_disposed) {
          error = _message(e);
          notifyListeners();
        }
        completer.completeError(e, stack);
        await refresh();
      } finally {
        _writing = false;
        if (_deferredGeneration > generation) unawaited(refresh());
        _deferredGeneration = -1;
      }
    });
    return completer.future;
  }

  Future<FavoriteUndo?> toggleFavorite(String id) {
    final before = _summary(id);
    if (before == null) return Future.value(null);
    final token = Object();
    final value = !before.favorite;
    (_favoriteWrites[id] ??= []).add((token: token, value: value));
    _projectFavorites();
    notifyListeners();
    return _mutate(() async {
      try {
        final snapshot = await _favorite(id, value);
        final after = snapshot.summaries.where((r) => r.id == id).first;
        return FavoriteUndo(
          id: id,
          before: before.favorite,
          after: after.favorite,
          revision: after.revision,
        );
      } finally {
        final pending = _favoriteWrites[id]!;
        pending.removeWhere((write) => identical(write.token, token));
        if (pending.isEmpty) _favoriteWrites.remove(id);
        _projectFavorites();
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<LibraryChangeResult> addLibraryTag(
    int expected,
    List<String> ids,
    String tag,
  ) => _mutate(() async {
    if (generation != expected) throw StateError('The Library changed.');
    final result = await (repository as LibraryRepository).addLibraryTag(
      expected,
      ids,
      tag,
    );
    _apply(result.snapshot);
    error = null;
    return result;
  });

  Future<LibraryChangeResult> changeLibraryNames(
    int expectedGeneration,
    bool tags,
    List<String> sources,
    String? target,
  ) => _mutate(() async {
    if (generation != expectedGeneration) {
      throw StateError('The Library changed. Review the names again.');
    }
    final result = await (repository as LibraryRepository).changeLibraryNames(
      generation,
      tags,
      sources,
      target,
    );
    _apply(result.snapshot);
    return result;
  });

  Future<void> undoLibraryNames(Object undo) => _mutate(() async {
    _apply(
      await (repository as LibraryRepository).undoLibraryNames(
        generation,
        undo,
      ),
    );
  });

  Future<core.CollectionSnapshot> _favorite(String id, bool value) async {
    final cached = _details[id];
    final amounts = _amounts[id];
    final snapshot = await repository.favorite(generation, id, value);
    _apply(snapshot, notify: false);
    final after = snapshot.summaries.where((r) => r.id == id).firstOrNull;
    // A successful generation-guarded favorite changes no recipe fields.
    if (cached != null &&
        after != null &&
        generation == snapshot.generation &&
        after.revision == cached.revision + 1) {
      _details[id] = core.Recipe(
        id: id,
        fields: cached.fields,
        favorite: after.favorite,
        createdAt: after.createdAt,
        updatedAt: after.updatedAt,
        revision: after.revision,
      );
      if (amounts != null) _amounts[id] = amounts;
    }
    error = null;
    notifyListeners();
    return snapshot;
  }

  Future<bool> undoFavorite(FavoriteUndo undo) => _mutate(() async {
    final current = _summary(undo.id);
    // Expire an Undo after any newer revision, including an ABA favorite edit.
    if (current == null ||
        current.revision != undo.revision ||
        current.favorite != undo.after) {
      return false;
    }
    await _favorite(undo.id, undo.before);
    return true;
  });
  Future<void> deleteRecipe(String id) => _mutate(() async {
    _apply(await repository.delete(generation, id));
    error = null;
  });
  Future<void> deleteRecipes(int expectedGeneration, List<String> ids) =>
      _mutate(() async {
        _apply(
          await (repository as BatchDeleteRepository).deleteMany(
            expectedGeneration,
            ids,
          ),
        );
        error = null;
      });
  Future<core.Recipe> saveRecipe({
    core.Recipe? base,
    required core.RecipeFields fields,
  }) => _mutate(() async {
    final editor = repository as EditorRecipeRepository;
    final beforeIds = summaries.map((r) => r.id).toSet();
    final snapshot = await editor.save(generation, base, fields);
    final summary = base == null
        ? snapshot.summaries.singleWhere((r) => !beforeIds.contains(r.id))
        : snapshot.summaries.singleWhere((r) => r.id == base.id);
    // Build the committed result without a fallible post-commit detail read.
    final saved = core.Recipe(
      id: summary.id,
      fields: fields,
      favorite: summary.favorite,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      revision: summary.revision,
    );
    _apply(snapshot, notify: false);
    if (_summary(saved.id)?.revision == saved.revision) {
      _details[saved.id] = saved;
    }
    error = null;
    notifyListeners();
    return saved;
  });
  Future<BackupPreview> previewRestore(Uint8List bytes) =>
      repository.previewRestore(bytes);
  Future<core.Recipe> importRecipe({
    required int generation,
    required core.RecipeFields fields,
    core.DuplicateChoice? choice,
  }) => _mutate(() async {
    final beforeIds = summaries.map((r) => r.id).toSet();
    final snapshot = await (repository as ImportRecipeRepository).importOne(
      generation,
      fields,
      choice,
    );
    final replacementId = choice is core.DuplicateChoice_Replace
        ? choice.id
        : null;
    final summary = snapshot.summaries.singleWhere(
      (r) => replacementId == null
          ? !beforeIds.contains(r.id)
          : r.id == replacementId,
    );
    final saved = core.Recipe(
      id: summary.id,
      fields: fields,
      favorite: summary.favorite,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      revision: summary.revision,
    );
    _apply(snapshot, notify: false);
    if (_summary(saved.id)?.revision == saved.revision) {
      _details[saved.id] = saved;
    }
    error = null;
    notifyListeners();
    return saved;
  });
  Future<core.RestoreReport> restoreBackup(BackupPreview preview) =>
      _mutate(() async {
        _apply(await repository.restore(preview));
        error = null;
        return preview.report;
      });
  String _message(Object e) =>
      e is core.ServiceError ? e.message : e.toString();
  void _preferencesChanged() {
    if (!_disposed) {
      _refreshVisible();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _search?.dispose();
    _shoppingCount.dispose();
    if (_subscriptionReady?.isCompleted == false) {
      _subscriptionReady!.complete();
    }
    preferences.removeListener(_preferencesChanged);
    _reconnect?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(repository.close());
    super.dispose();
  }
}
