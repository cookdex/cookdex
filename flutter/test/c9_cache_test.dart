import 'dart:async';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

Recipe _resolvedRecipe(Recipe original) {
  final fields = original.fields;
  final ingredient = fields.ingredients.single;
  return Recipe(
    id: original.id,
    revision: original.revision,
    favorite: original.favorite,
    createdAt: original.createdAt,
    updatedAt: original.updatedAt,
    fields: RecipeFields(
      title: fields.title,
      description: fields.description,
      servings: fields.servings,
      prepTime: fields.prepTime,
      cookTime: fields.cookTime,
      totalTime: fields.totalTime,
      source: fields.source,
      tags: fields.tags,
      notes: fields.notes,
      steps: ['Chill the resolved recipe overnight.'],
      ingredients: [
        Ingredient(
          amount: const Amount.rational(numerator: 2, denominator: 1),
          unit: ingredient.unit,
          name: ingredient.name,
          prepNote: ingredient.prepNote,
          optional: ingredient.optional,
          section: ingredient.section,
        ),
      ],
    ),
  );
}

class _CacheRepository extends FakeRepository {
  _CacheRepository() : super([recipe('a')]);
  Completer<List<String>>? amountGate;

  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async {
    amountCalls++;
    if (amountGate != null) {
      final gate = amountGate!;
      amountGate = null;
      return gate.future;
    }
    return ingredients
        .map(
          (ingredient) => switch (ingredient.amount) {
            Amount_Rational(:final numerator, :final denominator) =>
              denominator == 1 ? '$numerator' : '$numerator/$denominator',
            Amount_Range(
              :final lowerNumerator,
              :final lowerDenominator,
              :final upperNumerator,
              :final upperDenominator,
            ) =>
              '${lowerDenominator == 1 ? lowerNumerator : '$lowerNumerator/$lowerDenominator'}–${upperDenominator == 1 ? upperNumerator : '$upperNumerator/$upperDenominator'}',
            Amount_ToTaste() => 'to taste',
            Amount_Unspecified() => '',
          },
        )
        .toList();
  }
}

void main() {
  late _CacheRepository repository;
  late RecipeStore store;
  late LocalPreferences preferences;

  setUp(() async {
    repository = _CacheRepository();
    preferences = LocalPreferences.memory();
    store = RecipeStore(repository, preferences);
    await store.initialize();
  });
  tearDown(() {
    store.dispose();
    preferences.dispose();
  });

  for (final viaStream in [true, false]) {
    final source = viaStream ? 'reconnect snapshot' : 'external refresh';
    Future<void> publish(Recipe resolved) async {
      repository.recipes[resolved.id] = resolved;
      repository.generation++;
      if (viaStream) {
        repository.events.add(CollectionEvent.snapshot(repository.current));
      } else {
        await store.refresh();
      }
    }

    test(
      '$source invalidates cached body and amounts despite identical summaries',
      () async {
        final original = (await store.detail('a'))!;
        expect(await store.ingredientAmounts('a'), ['33/100']);
        final row = store.summaries.single;
        final resolved = _resolvedRecipe(original);
        await publish(resolved);
        // The revision, timestamp and every summary field stay equal; only the
        // canonical steps and amount changed in the newer causal generation.
        expect(store.summaries.single, same(row));
        expect(store.cachedDetail('a'), isNull);
        expect(await store.detail('a'), same(resolved));
        expect((await store.detail('a'))!.fields.steps, [
          'Chill the resolved recipe overnight.',
        ]);
        expect(await store.ingredientAmounts('a'), ['2']);
        expect(repository.detailCalls, 2);
        expect(repository.amountCalls, 2);
      },
    );

    test(
      '$source discards an old in-flight detail and reloads the resolved body',
      () async {
        final original = repository.recipes['a']!;
        final oldRequest = Completer<Recipe?>();
        repository.detailGate = oldRequest;
        final pending = store.detail('a');
        expect(repository.detailCalls, 1);
        final resolved = _resolvedRecipe(original);
        await publish(resolved);
        oldRequest.complete(original);
        expect(await pending, same(resolved));
        expect(store.cachedDetail('a'), same(resolved));
        expect(await store.ingredientAmounts('a'), ['2']);
        expect(repository.detailCalls, 2);
      },
    );

    test('$source discards old in-flight amount formatting', () async {
      final original = (await store.detail('a'))!;
      final oldFormatting = Completer<List<String>>();
      repository.amountGate = oldFormatting;
      final pending = store.ingredientAmounts('a');
      // Let the cached detail Future reach the formatter before the snapshot.
      await Future<void>.delayed(Duration.zero);
      expect(repository.amountCalls, 1);
      final resolved = _resolvedRecipe(original);
      await publish(resolved);
      oldFormatting.complete(['33/100']);
      expect(await pending, ['2']);
      expect(await store.ingredientAmounts('a'), ['2']);
      expect(store.cachedDetail('a'), same(resolved));
      expect(repository.amountCalls, 2);
    });
  }
}
