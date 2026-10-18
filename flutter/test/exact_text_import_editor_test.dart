import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/text_import_review.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportRepositoryFake;
import 'recipe_store_test.dart' show recipe;

Recipe exactFixture() {
  final json = recipeToJson(recipe('incoming'));
  final fields = json['fields'] as Map<String, dynamic>;
  fields['prepTime'] = 'about 10 minutes';
  fields['cookTime'] = '1 hour';
  fields['totalTime'] = 'roughly 70 min';
  fields['tags'] = ['Quick', 'UPPER Case'];
  fields['notes'] = 'Keep These Notes';
  return recipeFromJson(json);
}

class NormalizingRepository extends ImportRepositoryFake {
  NormalizingRepository(super.recipes);
  int normalizations = 0;
  @override
  Future<RecipeFields> normalizeEditorFields(
    RecipeFields fields,
    List<String?> amountInputs,
  ) async {
    normalizations++;
    await super.normalizeEditorFields(fields, amountInputs);
    return RecipeFields(
      title: fields.title,
      description: fields.description,
      servings: fields.servings,
      prepTime: '10 min',
      cookTime: '60 min',
      totalTime: '70 min',
      source: fields.source,
      notes: fields.notes,
      tags: fields.tags.map((t) => t.toLowerCase()).toList(),
      ingredients: fields.ingredients,
      steps: fields.steps,
    );
  }
}

void main() {
  for (final accept in [false, true]) {
    test(
      'exact import spelling review changes only consented names: $accept',
      () async {
        final json = recipeToJson(exactFixture());
        (json['fields'] as Map<String, dynamic>)['tags'] = [
          'QUICK',
          'UPPER Case',
        ];
        final source = recipeFromJson(json);
        final repo = NormalizingRepository([recipe('existing')]);
        final store = RecipeStore(repo, LocalPreferences.memory());
        await store.initialize();
        addTearDown(store.dispose);
        final editor = await EditorController.create(
          store: store,
          storage: MemoryDraftStorage(),
          imported: Candidate(
            recipe: source,
            warnings: const [],
            ingredientSources: const [],
          ),
          exactTextImport: true,
        );
        addTearDown(editor.dispose);
        var reviews = 0;
        final saved = await editor.save(
          reviewNames: (matches) async {
            reviews++;
            expect(matches, hasLength(1));
            return accept ? {0} : <int>{};
          },
        );
        expect(reviews, 1);
        expect(saved, isNotNull);
        expect(saved!.fields.tags, [accept ? 'Quick' : 'QUICK', 'UPPER Case']);
        expect(saved.fields.prepTime, source.fields.prepTime);
        expect(saved.fields.cookTime, source.fields.cookTime);
        expect(saved.fields.totalTime, source.fields.totalTime);
        expect(
          saved.fields.ingredients.single.name,
          source.fields.ingredients.single.name,
        );
      },
    );
  }
  test(
    'exact Text v1 validates but retains durations, spelling and every field',
    () async {
      final source = exactFixture();
      final repo = NormalizingRepository([]);
      final store = RecipeStore(repo, LocalPreferences.memory());
      await store.initialize();
      addTearDown(store.dispose);
      final editor = await EditorController.create(
        store: store,
        storage: MemoryDraftStorage(),
        imported: Candidate(
          recipe: source,
          warnings: const [],
          ingredientSources: const [],
        ),
        exactTextImport: true,
      );
      addTearDown(editor.dispose);
      final saved = await editor.save();
      expect(saved, isNotNull);
      expect(repo.normalizations, 1);
      expect(sameTextRecipe(source, saved!), isTrue);
      expect(repo.choice, const DuplicateChoice.keepBoth());
    },
  );

  test('same-title exact Text v1 cannot take replacement branch', () async {
    final existing = recipe('existing');
    final source = exactFixture();
    final repo = NormalizingRepository([existing]);
    final store = RecipeStore(repo, LocalPreferences.memory());
    await store.initialize();
    addTearDown(store.dispose);
    final editor = await EditorController.create(
      store: store,
      storage: MemoryDraftStorage(),
      imported: Candidate(
        recipe: source,
        warnings: const [],
        ingredientSources: const [],
      ),
      exactTextImport: true,
    );
    addTearDown(editor.dispose);
    var duplicateChoices = 0;
    final saved = await editor.save(
      chooseDuplicate: (_) async {
        duplicateChoices++;
        return const DuplicateChoice.replace(id: 'existing');
      },
    );
    expect(saved, isNotNull);
    expect(duplicateChoices, 0);
    expect(repo.choice, const DuplicateChoice.keepBoth());
    expect(repo.recipes, hasLength(2));
    expect(sameTextRecipe(repo.recipes['existing']!, existing), isTrue);
  });

  test(
    'draft recovery retains exact-import flag and field preservation',
    () async {
      final source = exactFixture();
      final repo = NormalizingRepository([]);
      final store = RecipeStore(repo, LocalPreferences.memory());
      await store.initialize();
      addTearDown(store.dispose);
      final storage = MemoryDraftStorage();
      final editor = await EditorController.create(
        store: store,
        storage: storage,
        imported: Candidate(
          recipe: source,
          warnings: const [],
          ingredientSources: const [],
        ),
        exactTextImport: true,
      );
      await editor.flush();
      final recovery = editor.draft.toJson();
      editor.dispose();
      final recovered = await EditorController.create(
        store: store,
        storage: storage,
        recovered: recovery,
      );
      addTearDown(recovered.dispose);
      expect(recovered.draft.exactTextImport, isTrue);
      expect(recovered.draft.imported, isTrue);
      final saved = await recovered.save();
      expect(saved, isNotNull);
      expect(sameTextRecipe(source, saved!), isTrue);
    },
  );
}
