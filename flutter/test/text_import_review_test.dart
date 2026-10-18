import 'dart:async';

import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/text_import_review.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakeService, ImportRepositoryFake;
import 'recipe_store_test.dart' show recipe, summary;

TextImportBlock block(Recipe r) => TextImportBlock(
  text: r.fields.title,
  candidate: Candidate(
    recipe: r,
    warnings: const [],
    ingredientSources: const [],
  ),
);

class PartialRepository extends ImportRepositoryFake {
  PartialRepository() : super([]);
  bool failSecond = true;
  @override
  Future<CollectionSnapshot> importOne(
    int generation,
    RecipeFields fields,
    DuplicateChoice? choice,
  ) {
    if (failSecond && imports == 1) throw StateError('Synthetic failure');
    return super.importOne(generation, fields, choice);
  }
}

class SmartFake extends ImportFakeService implements SmartTextImportService {
  final gate = Completer<ImportDiscovery>();
  int calls = 0;
  @override
  Future<ImportDiscovery> smartText(String text) {
    calls++;
    return gate.future;
  }
}

void main() {
  test('exact comparison ignores metadata and compares all content', () {
    final first = recipe('one');
    expect(
      sameTextRecipe(first, recipe('two', favorite: true, revision: 2)),
      isTrue,
    );
    expect(sameTextRecipe(first, recipe('two', notes: 'different')), isFalse);
    expect(
      sameTextRecipe(first, recipe('two', description: 'different')),
      isFalse,
    );
  });

  test('combined matches share choices and preserve unaccepted fields', () {
    final fields = recipe('one').fields;
    final changed = RecipeFields(
      title: fields.title,
      description: fields.description,
      servings: fields.servings,
      prepTime: fields.prepTime,
      cookTime: fields.cookTime,
      totalTime: fields.totalTime,
      source: fields.source,
      notes: fields.notes,
      steps: fields.steps,
      ingredients: fields.ingredients,
      tags: ['  QUICK  ', 'Other  tag'],
    );
    final matches = textImportNameMatches(
      [changed, changed],
      [summary(recipe('existing'))],
    );
    expect(matches, hasLength(1));
    expect(matches.single.preferred, 'Quick');
    expect(
      identical(applyTextImportNames(changed, matches, {}), changed),
      isTrue,
    );
    final applied = applyTextImportNames(changed, matches, {0});
    expect(applied.tags, ['Quick', 'Other  tag']);
    expect(applied.steps, fields.steps);
    expect(applied.ingredients.single.name, fields.ingredients.single.name);
  });

  for (final size in [
    const Size(320, 780),
    const Size(390, 844),
    const Size(412, 915),
    const Size(1280, 800),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('review labels and selection fit $size dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = ImportRepositoryFake([recipe('existing')]);
        final store = RecipeStore(repo, LocalPreferences.memory());
        await store.initialize();
        addTearDown(store.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: cookdexTheme(
              colors: ColorScheme.fromSeed(
                seedColor: Colors.green,
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(size.width == 412 ? 2 : 1),
              ),
              child: child!,
            ),
            home: TextImportReview(
              blocks: [
                block(recipe('copy')),
                block(recipe('different', notes: 'A different recipe')),
                const TextImportBlock(text: 'Malformed fixture'),
              ],
              store: store,
              service: ImportFakeService(),
              onReview: (_, _) async => null,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Already in your library'), findsOneWidget);
        expect(find.text('Same name as one you have'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('text-import-0')),
              )
              .value,
          false,
        );
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('text-import-1')),
              )
              .value,
          true,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'partial failure retries only unsaved rows and always keeps both',
    (tester) async {
      final repo = PartialRepository();
      final store = RecipeStore(repo, LocalPreferences.memory());
      await store.initialize();
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TextImportReview(
            blocks: [
              block(recipe('one', title: 'First')),
              block(recipe('two', title: 'Second')),
            ],
            store: store,
            service: ImportFakeService(),
            onReview: (_, _) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import selected (2)'));
      await tester.pumpAndSettle();
      expect(repo.imports, 1);
      expect(repo.choice, const DuplicateChoice.keepBoth());
      expect(find.textContaining('1 imported.'), findsOneWidget);
      repo.failSecond = false;
      await tester.tap(find.text('Import selected (1)'));
      await tester.pumpAndSettle();
      expect(repo.imports, 2);
      expect(repo.recipes.length, 2);
    },
  );

  testWidgets('stale library refreshes selection before saving', (
    tester,
  ) async {
    final repo = ImportRepositoryFake([]);
    final store = RecipeStore(repo, LocalPreferences.memory());
    await store.initialize();
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TextImportReview(
          blocks: [block(recipe('incoming'))],
          store: store,
          service: ImportFakeService(),
          onReview: (_, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.changed(recipe('arrived'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import selected (1)'));
    await tester.pumpAndSettle();
    expect(repo.imports, 0);
    expect(find.text('Already in your library'), findsOneWidget);
    expect(find.text('Import selected (0)'), findsOneWidget);
  });

  testWidgets('cancelled explicit Smart Import ignores its late result', (
    tester,
  ) async {
    final repo = ImportRepositoryFake([]);
    final store = RecipeStore(repo, LocalPreferences.memory());
    final service = SmartFake();
    await store.initialize();
    addTearDown(store.dispose);
    var reviewed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TextImportReview(
          blocks: const [TextImportBlock(text: 'Malformed fixture')],
          store: store,
          service: service,
          onReview: (_, _) async {
            reviewed++;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    await tester.tap(find.text('Try Smart Import'));
    await tester.pump();
    expect(service.calls, 1);
    await tester.tap(find.text('Cancel'));
    service.gate.complete(
      ImportDiscovery(candidates: [block(recipe('late')).candidate!]),
    );
    await tester.pumpAndSettle();
    expect(reviewed, 0);
    expect(repo.imports, 0);
  });
}
