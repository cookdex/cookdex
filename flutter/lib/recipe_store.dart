import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_preferences.dart';
import 'src/rust/api.dart' as core;

class BackupPreview {
  const BackupPreview(this.report, this.token);
  final core.RestoreReport report;
  final Object token;
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

abstract interface class SetAsideRepository {
  Future<core.CollectionSnapshot> discardSetAside(int generation);
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
        EditorRecipeRepository,
        ShoppingRepository,
        ImportRecipeRepository,
        SetAsideRepository,
        ScalingRepository {
  RustRecipeRepository(this.session);
  final core.CoreSession session;
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
  final Map<String, Map<SearchField, String>> _search = {};
  final Map<String, int> _versions = {};
  final Map<String, Future<core.Recipe?>> _pending = {};
  final Map<String, Future<List<String>>> _pendingAmounts = {};
  StreamSubscription<core.CollectionEvent>? _subscription;
  Timer? _reconnect;
  Future<void>? _refresh;
  bool _refreshAgain = false;
  Future<void> _mutations = Future.value();
  bool _writing = false;
  int _deferredGeneration = -1;
  List<core.RecipeSummary> get summaries => _snapshot?.summaries ?? const [];
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
  int get uncheckedShoppingCount =>
      _snapshot?.shopping.where((i) => !i.checked).length ?? 0;

  /// Literal every-word matching over cached fields: this getter does no I/O.
  List<core.RecipeSummary> get visibleRecipes {
    final words = preferences.query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final result = summaries.where((r) {
      if (preferences.favoritesOnly && !r.favorite) return false;
      final projection = _search[r.id]!;
      return words.every(
        (word) => preferences.searchFields.any(
          (field) => projection[field]!.contains(word),
        ),
      );
    }).toList();
    result.sort((a, b) {
      final primary = switch (preferences.sort) {
        RecipeSort.edited => b.updatedAt.compareTo(a.updatedAt),
        RecipeSort.added => b.createdAt.compareTo(a.createdAt),
        RecipeSort.title => a.title.toLowerCase().compareTo(
          b.title.toLowerCase(),
        ),
      };
      return primary == 0 ? a.id.compareTo(b.id) : primary;
    });
    return result;
  }

  Future<void> initialize() async {
    _listen();
    await refresh();
  }

  void _listen() {
    if (_disposed) return;
    _subscription = repository.subscribe().listen(
      (event) {
        if (_disposed) return;
        switch (event) {
          case core.CollectionEvent_Snapshot(:final field0):
            _apply(field0, external: true);
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
      onError: (Object e) {
        _connectionLost(e);
      },
      onDone: () {
        _connectionLost(null);
      },
    );
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
        _listen();
        await refresh();
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
    final before = {for (final r in summaries) r.id: r};
    // FRB decodes a fresh object graph for every snapshot. Retain equal row
    // objects so visible rows can skip rebuilding after unrelated mutations.
    final stableSummaries = snapshot.summaries
        .map((r) {
          final previous = before[r.id];
          return previous != null && _sameSummary(previous, r) ? previous : r;
        })
        .toList(growable: false);
    final after = {for (final r in stableSummaries) r.id: r};
    for (final id in {...before.keys, ...after.keys}) {
      if (!identical(before[id], after[id])) {
        _invalidate(id);
        _search.remove(id);
      }
      final r = after[id];
      if (r != null) {
        _search.putIfAbsent(
          id,
          () => {
            SearchField.title: r.title.toLowerCase(),
            SearchField.ingredients: r.ingredients.join(' ').toLowerCase(),
            SearchField.tags: r.tags.join(' ').toLowerCase(),
            SearchField.notes: r.notes.toLowerCase(),
            SearchField.description: r.description.toLowerCase(),
          },
        );
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
    loading = false;
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

  Future<FavoriteUndo?> toggleFavorite(String id) => _mutate(() async {
    final before = _summary(id);
    if (before == null) return null;
    final snapshot = await _favorite(id, !before.favorite);
    final after = snapshot.summaries.where((r) => r.id == id).first;
    return FavoriteUndo(
      id: id,
      before: before.favorite,
      after: after.favorite,
      revision: after.revision,
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
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    preferences.removeListener(_preferencesChanged);
    _reconnect?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(repository.close());
    super.dispose();
  }
}
