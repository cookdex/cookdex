import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';

Recipe recipe(
  String id, {
  String title = 'Lemon cake',
  bool favorite = false,
  int revision = 1,
  String notes = 'overnight',
  String description = 'soft crumb',
}) => Recipe(
  id: id,
  favorite: favorite,
  revision: revision,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-0$revision',
  fields: RecipeFields(
    title: title,
    description: description,
    servings: '4',
    prepTime: '10 min',
    cookTime: '',
    totalTime: '',
    source: '',
    tags: ['Quick'],
    notes: notes,
    ingredients: [
      const Ingredient(
        amount: Amount.rational(numerator: 33, denominator: 100),
        unit: 'cup',
        name: 'cream [fresh]',
        prepNote: '',
        optional: false,
        section: '',
      ),
    ],
    steps: ['Mix', 'Bake'],
  ),
);
RecipeSummary summary(Recipe r) => RecipeSummary(
  id: r.id,
  title: r.fields.title,
  description: r.fields.description,
  ingredients: r.fields.ingredients.map((i) => i.name).toList(),
  tags: r.fields.tags,
  notes: r.fields.notes,
  favorite: r.favorite,
  createdAt: r.createdAt,
  updatedAt: r.updatedAt,
  revision: r.revision,
  servings: r.fields.servings,
  prepTime: r.fields.prepTime,
  cookTime: r.fields.cookTime,
  totalTime: r.fields.totalTime,
);

class FakeRepository implements RecipeRepository {
  FakeRepository(List<Recipe> recipes)
    : recipes = {for (final r in recipes) r.id: r};
  final Map<String, Recipe> recipes;
  int generation = 0,
      snapshotCalls = 0,
      detailCalls = 0,
      amountCalls = 0,
      favoriteCalls = 0;
  final events = StreamController<CollectionEvent>.broadcast(sync: true);
  Completer<Recipe?>? detailGate;
  Completer<CollectionSnapshot>? snapshotGate;
  CollectionSnapshot get current => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: generation,
    summaries: recipes.values.map(summary).toList(),
    shopping: [],
    conflicts: [],
    hasPrevious: generation > 0,
  );
  @override
  Future<CollectionSnapshot> snapshot() async {
    snapshotCalls++;
    return snapshotGate?.future ?? current;
  }

  @override
  Stream<CollectionEvent> subscribe() => events.stream;
  @override
  Future<Recipe?> detail(String id) async {
    detailCalls++;
    if (detailGate != null) {
      final gate = detailGate!;
      detailGate = null;
      return gate.future;
    }
    return recipes[id];
  }

  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async {
    amountCalls++;
    return ingredients.map((_) => '33/100').toList();
  }

  void changed(Recipe r) {
    recipes[r.id] = r;
    generation++;
    events.add(
      CollectionEvent.change(
        ChangeBatch(
          generation: generation,
          changed: [r.id],
          deleted: [],
          shoppingChanged: false,
          conflictsChanged: false,
        ),
      ),
    );
  }

  @override
  Future<CollectionSnapshot> favorite(
    int generation,
    String id,
    bool value,
  ) async {
    favoriteCalls++;
    if (generation != this.generation) {
      throw const ServiceError(code: ErrorCode.staleWrite, message: 'Changed');
    }
    final old = recipes[id]!;
    changed(
      Recipe(
        id: id,
        fields: old.fields,
        favorite: value,
        createdAt: old.createdAt,
        updatedAt: '2026-02-01',
        revision: old.revision + 1,
      ),
    );
    return current;
  }

  @override
  Future<CollectionSnapshot> delete(int generation, String id) async {
    recipes.remove(id);
    this.generation++;
    return current;
  }

  @override
  Future<BackupPreview> previewRestore(Uint8List bytes) async =>
      const BackupPreview(
        RestoreReport(
          shoppingSetup: false,
          added: 1,
          updated: 0,
          skipped: 0,
          conflicts: [],
        ),
        'preview',
      );
  @override
  Future<CollectionSnapshot> restore(BackupPreview preview) async {
    changed(recipe('restored'));
    return current;
  }

  @override
  Future<void> close() => events.close();
}

Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late LocalPreferences prefs;
  late FakeRepository repository;
  late RecipeStore store;
  setUp(() async {
    prefs = LocalPreferences.memory();
    repository = FakeRepository([
      recipe('a'),
      recipe('b', title: 'Soup', favorite: true),
    ]);
    store = RecipeStore(repository, prefs);
    await store.initialize();
  });
  tearDown(() {
    store.dispose();
    prefs.dispose();
  });

  test(
    'five-field literal every-word search stays entirely in cached summaries',
    () {
      final snapshots = repository.snapshotCalls;
      prefs.setQuery('LEMON cream quick');
      expect(store.visibleRecipes.map((r) => r.id), ['a']);
      prefs.setQuery('overnight');
      expect(store.visibleRecipes, isEmpty);
      prefs.setSearchFields({...prefs.searchFields, SearchField.notes});
      expect(store.visibleRecipes.length, 2);
      prefs.setSearchFields({SearchField.description});
      prefs.setQuery('soft crumb');
      expect(store.visibleRecipes.length, 2);
      prefs.setSearchFields({SearchField.ingredients});
      prefs.setQuery('[fresh]');
      expect(store.visibleRecipes.length, 2);
      prefs.setQuery('title:Lemon');
      expect(store.visibleRecipes, isEmpty);
      prefs.setQuery('"cream"');
      expect(store.visibleRecipes, isEmpty);
      prefs.resetSearch();
      prefs.setFavoritesOnly(true);
      expect(store.visibleRecipes.single.id, 'b');
      expect(repository.snapshotCalls, snapshots);
      expect(repository.detailCalls, 0);
    },
  );
  test(
    'detail is lazy, shares in-flight reads and caches exact formatting',
    () async {
      expect(repository.detailCalls, 0);
      final values = await Future.wait([store.detail('a'), store.detail('a')]);
      expect(identical(values[0], values[1]), true);
      await store.ingredientAmounts('a');
      await store.ingredientAmounts('a');
      expect(repository.detailCalls, 1);
      expect(repository.amountCalls, 1);
    },
  );
  test(
    'favorite and Undo patch only their detail without detail/format refetch',
    () async {
      await store.detail('a');
      await store.detail('b');
      await store.ingredientAmounts('a');
      final other = store.cachedDetail('b');
      final originalSummary = store.summaries.firstWhere((r) => r.id == 'a');
      final otherSummary = store.summaries.firstWhere((r) => r.id == 'b');
      final undo = await store.toggleFavorite('a');
      await settle();
      expect(store.cachedDetail('a')!.favorite, true);
      expect(identical(store.cachedDetail('b'), other), true);
      expect(
        identical(store.summaries.firstWhere((r) => r.id == 'b'), otherSummary),
        true,
      );
      expect(
        identical(
          store.summaries.firstWhere((r) => r.id == 'a'),
          originalSummary,
        ),
        false,
      );
      expect(await store.undoFavorite(undo!), true);
      expect(
        identical(store.summaries.firstWhere((r) => r.id == 'b'), otherSummary),
        true,
      );
      expect(store.cachedDetail('a')!.favorite, false);
      expect(await store.ingredientAmounts('a'), ['33/100']);
      expect(repository.detailCalls, 2);
      expect(repository.amountCalls, 1);
    },
  );
  test(
    'equivalent bridge snapshots preserve row objects including list fields',
    () async {
      final originals = {for (final row in store.summaries) row.id: row};
      // The fake mirrors FRB: each snapshot constructs fresh DTOs and list fields.
      await store.refresh();
      for (final row in store.summaries) {
        expect(identical(row, originals[row.id]), true);
      }
      repository.changed(recipe('a', title: 'Changed title', revision: 2));
      await settle();
      expect(
        identical(
          store.summaries.firstWhere((r) => r.id == 'a'),
          originals['a'],
        ),
        false,
      );
      expect(
        identical(
          store.summaries.firstWhere((r) => r.id == 'b'),
          originals['b'],
        ),
        true,
      );
    },
  );
  test(
    'favorite Undo cannot overwrite a subsequent edit or favorite ABA',
    () async {
      final undo = (await store.toggleFavorite('a'))!;
      repository.changed(
        recipe('a', title: 'New title', favorite: true, revision: 3),
      );
      await settle();
      expect(await store.undoFavorite(undo), false);
      expect(repository.recipes['a']!.fields.title, 'New title');
      expect(repository.favoriteCalls, 1);
    },
  );
  test(
    'late detail is discarded when a newer collection event arrives',
    () async {
      final old = repository.recipes['a']!;
      final gate = Completer<Recipe?>();
      repository.detailGate = gate;
      final pending = store.detail('a');
      await settle();
      repository.changed(recipe('a', title: 'Updated', revision: 2));
      gate.complete(old);
      expect((await pending)!.fields.title, 'Updated');
      expect(store.cachedDetail('a')!.revision, 2);
    },
  );
  test('older snapshot cannot roll back a subscription snapshot', () async {
    final old = repository.current;
    final gate = Completer<CollectionSnapshot>();
    repository.snapshotGate = gate;
    final refreshing = store.refresh();
    repository.recipes['a'] = recipe('a', title: 'New', revision: 2);
    repository.generation = 5;
    repository.events.add(CollectionEvent.snapshot(repository.current));
    gate.complete(old);
    await refreshing;
    expect(store.generation, 5);
    expect(store.summaries.first.title, 'New');
  });
  test('restore uses preview and refreshes visible summaries', () async {
    final preview = await store.previewRestore(Uint8List(0));
    final report = await store.restoreBackup(preview);
    expect(report.added, 1);
    expect(store.summaries.any((r) => r.id == 'restored'), true);
  });
  test(
    'fresh preferences round-trip all list and cook state; Reset defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'cookdex-prefs-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/local.json';
      final local = await LocalPreferences.load(path);
      local.setQuery('cake');
      local.setSearchFields({SearchField.notes});
      local.setView(RecipeView.compact);
      local.setSort(RecipeSort.title);
      local.setFavoritesOnly(true);
      local.setScrollOffset(125);
      local.saveCook('a', 2, {1});
      await local.flush();
      final restored = await LocalPreferences.load(path);
      expect(restored.query, 'cake');
      expect(restored.searchFields, {SearchField.notes});
      expect(restored.view, RecipeView.compact);
      expect(restored.sort, RecipeSort.title);
      expect(restored.favoritesOnly, true);
      expect(restored.scrollOffset, 125);
      expect(restored.cookStep('a'), 2);
      expect(restored.cookChecks('a'), {1});
      restored.resetSearch();
      expect(restored.query, '');
      expect(restored.searchFields, LocalPreferences.defaultSearchFields);
      expect(restored.view, RecipeView.cards);
      expect(restored.sort, RecipeSort.edited);
      expect(restored.scrollOffset, 0);
      await restored.flush();
      local.dispose();
      restored.dispose();
      await local.flush();
      await restored.flush();
    },
  );
}
