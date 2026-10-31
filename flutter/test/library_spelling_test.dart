import 'dart:io';
import 'dart:math';

import 'package:cookdex/editor_model.dart';
import 'package:cookdex/library_catalog.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/name_spelling.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/components.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'library_screen_test.dart';
import 'recipe_store_test.dart' show recipe, summary;

List<Recipe> spellingFixtures() {
  const groups = [
    ['beef', 'Beef', 'Qeef'],
    ['cornstarch', 'corn starch'],
    ['cumin', 'cummin'],
    ['diced green chiles', 'diced green chilies'],
    ['mozzarella', 'mozarella'],
    ['turmeric', 'tumeric'],
    ['ham', 'Ham'],
    ['egg', 'eggs', '1% milk', '2% milk', 'yam', 'butter', 'peanut butter'],
  ];
  return [
    for (var i = 0; i < 12; i++)
      recipeFromJson(() {
        final json = recipeToJson(recipe('spelling-$i'));
        final fields = json['fields'] as Map<String, dynamic>;
        fields['title'] = 'Garden supper ${i + 1}';
        final names = [for (final g in groups) g[i % g.length]];
        fields['tags'] = names;
        fields['ingredients'] = [
          for (final n in names)
            {
              'name': n,
              'amount': {'kind': 'rational', 'numerator': 1, 'denominator': 2},
              'unit': 'cup',
              'prepNote': '',
              'optional': false,
              'section': '',
            },
        ];
        return json;
      }()),
  ];
}

void main() {
  test(
    'Typo matching examples, exclusions, transpositions and two long edits',
    () {
      for (final pair in [
        ('beef', 'Qeef'),
        ('ham', 'Ham'),
        ('diced green chiles', 'diced green chilies'),
        ('cornstarch', 'corn starch'),
        ('cumin', 'cummin'),
        ('turmeric', 'tumeric'),
        ('mozzarella', 'mozarella'),
        ('beef', 'beet'),
        ('peas', 'pears'),
        ('cumin', 'cuimn'),
        ('cornstarch', 'constach'),
        ('green cardamom', 'grean cardamon'),
      ]) {
        expect(
          NameSpelling(pair.$1).sameOrSimilar(NameSpelling(pair.$2)),
          isTrue,
          reason: '$pair',
        );
        expect(
          NameSpelling(pair.$2).sameOrSimilar(NameSpelling(pair.$1)),
          isTrue,
          reason: '$pair',
        );
        expect(similarLibraryName(pair.$1, pair.$2), isTrue);
      }
      for (final pair in [
        ('egg', 'eggs'),
        ('carrot', 'carrots'),
        ('berry', 'berries'),
        ('leaf', 'leaves'),
        ('smoothie', 'smoothies'),
        ('dried chili', 'dried chilies'),
        ('goose egg', 'geese eggs'),
        ('1% milk', '2% milk'),
        ('ham', 'yam'),
        ('butter', 'peanut butter'),
        ('cumin', 'kummn'),
        ('cumin', 'cummins'),
      ]) {
        expect(
          NameSpelling(pair.$1).sameOrSimilar(NameSpelling(pair.$2)),
          isFalse,
          reason: '$pair',
        );
      }
      expect(
        similarLibraryName('egg', 'eggs'),
        isTrue,
      ); // Deliberate manual merge.
      expect(similarLibraryName('butter', 'peanut butter'), isFalse);
    },
  );

  test(
    'Groups use most-used anchor without chaining and retain all case variants',
    () {
      final fixtures = spellingFixtures().map(summary).toList();
      for (final kind in LibraryKind.values) {
        final catalog = LibraryCatalog(fixtures, kind);
        expect(catalog.duplicates, hasLength(7));
        expect(catalog.duplicates.first.map((n) => n.name), [
          'beef',
          'Beef',
          'Qeef',
        ]);
        expect(hasSimilarSpelling(catalog.duplicates.first), isTrue);
        expect(
          hasSimilarSpelling(
            catalog.duplicates.firstWhere((g) => g.first.name == 'ham'),
          ),
          isFalse,
        );
        expect(catalog.matchingTag('BEEF!')!.name, 'beef');
        expect(
          catalog.matchingTag('queef'),
          isNull,
        ); // No automatic fuzzy rename.
      }
      final names = ['aaaa', 'aaab', 'aabb'];
      final chain = [
        for (var i = 0; i < 6; i++)
          recipeFromJson(() {
            final json = recipeToJson(recipe('chain-$i'));
            (json['fields'] as Map<String, dynamic>)['tags'] = [
              names[i < 3
                  ? 0
                  : i < 5
                  ? 1
                  : 2],
            ];
            return json;
          }()),
      ];
      expect(
        LibraryCatalog(
          chain.map(summary).toList(),
          LibraryKind.tags,
        ).duplicates.single.map((n) => n.name),
        ['aaaa', 'aaab'],
      );
    },
  );

  test('Kept exact spellings persist locally, stay kind-specific and flag new spelling', () async {
    final dir = await Directory.systemTemp.createTemp('cookdex-spelling-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/preferences.json';
    final prefs = await LocalPreferences.load(path);
    prefs.keepSeparate('tags', ['Beef', 'beef', 'Qeef']);
    await prefs.flush();
    prefs.dispose();
    final restored = await LocalPreferences.load(path);
    expect(restored.isKeptSeparate('tags', ['beef', 'Beef']), isTrue);
    expect(restored.isKeptSeparate('ingredients', ['beef', 'Beef']), isFalse);
    expect(
      restored.isKeptSeparate('tags', ['beef', 'Beef', 'Qeef', 'beef!']),
      isFalse,
    );
    restored.showTogether('tags', ['Qeef', 'beef', 'Beef']);
    expect(restored.keptSeparate('tags'), isEmpty);
    await restored.flush();
    restored.dispose();
  });

  testWidgets('Keep separate, ten-second Undo and Show again when all hidden', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final (store, repo, prefs) = await libraryHarness(
      tester,
      recipes: spellingFixtures(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    });
    await tester.tap(find.text('Tags'));
    await tester.pumpAndSettle();
    expect(find.text('Similar spelling'), findsWidgets);
    await tester.tap(find.text('Keep separate').first);
    await tester.pumpAndSettle();
    expect(prefs.keptSeparate('tags'), hasLength(1));
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).duration,
      const Duration(seconds: 10),
    );
    expect(repo.changes, 0);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(prefs.keptSeparate('tags'), isEmpty);
    for (final g in LibraryCatalog(
      store.summaries,
      LibraryKind.tags,
    ).duplicates) {
      prefs.keepSeparate('tags', g.map((n) => n.name));
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-duplicates-card')), findsNothing);
    await tester.tap(find.text('Kept separate (7)'));
    await tester.pumpAndSettle();
    expect(find.text('No possible duplicates'), findsOneWidget);
    await tester.tap(find.text('Show again').first);
    await tester.pumpAndSettle();
    expect(prefs.keptSeparate('tags'), hasLength(6));
    expect(find.text('Merge'), findsOneWidget);
    expect(repo.changes, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Search X retains keyboard state and full-sized separated actions',
    (tester) async {
      final query = TextEditingController(text: 'beef');
      var cleared = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Scaffold(
            body: TextField(
              controller: query,
              decoration: InputDecoration(
                suffixIcon: SearchFieldActions(
                  controller: query,
                  onClear: () => cleared++,
                  onOptions: () {},
                ),
              ),
            ),
          ),
        ),
      );
      final clear = find.byTooltip('Clear search');
      final options = find.byTooltip('Search fields');
      expect(tester.getSize(clear).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(clear).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(options).width, greaterThanOrEqualTo(48));
      expect(tester.getTopLeft(options).dx - tester.getTopRight(clear).dx, 8);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput
          .hide(); // Android Back can hide the IME without blurring.
      await tester.tap(clear);
      await tester.pump();
      expect(query.text, isEmpty);
      expect(cleared, 1);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(options, findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      query.dispose();
    },
  );

  testWidgets('Library and merge searches clear their own text', (
    tester,
  ) async {
    final (store, _, prefs) = await libraryHarness(
      tester,
      recipes: spellingFixtures(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    });
    await tester.enterText(find.byType(TextField), 'cumin');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.enterText(find.byType(TextField), 'cumin');
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('library-name', false, 'cumin'))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge into…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'cum');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      isEmpty,
    );
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('Similar names'), findsOneWidget);
    expect(find.text('All names'), findsOneWidget);
  });

  test('500 recipes: fresh spelling catalog and cached reads', () async {
    final random = Random(714);
    String word() =>
        String.fromCharCodes(List.generate(14, (_) => 97 + random.nextInt(26)));
    final ingredients = List.generate(1000, (_) => word());
    final recipes = [
      for (var i = 0; i < 500; i++)
        recipeFromJson(() {
          final json = recipeToJson(recipe('scale-$i'));
          final fields = json['fields'] as Map<String, dynamic>;
          fields['tags'] = [ingredients[i], ingredients[i].toUpperCase()];
          fields['ingredients'] = [
            for (var j = 0; j < 12; j++)
              {
                'name': ingredients[(i * 7 + j) % 1000],
                'amount': {'kind': 'unspecified'},
                'unit': '',
                'prepNote': '',
                'optional': false,
                'section': '',
              },
          ];
          return json;
        }()),
    ].map(summary).toList();
    final start = Stopwatch()..start();
    final background = LibraryCatalog(recipes, LibraryKind.ingredients);
    final work = background.loadDuplicates();
    start.stop();
    expect(await work, isEmpty);
    // ignore: avoid_print
    print(
      '500-recipe initial catalog/background dispatch us: ${start.elapsedMicroseconds}',
    );
    final times = <int>[];
    for (var repeat = 0; repeat < 6; repeat++) {
      final watch = Stopwatch()..start();
      final catalog = LibraryCatalog(recipes, LibraryKind.ingredients);
      expect(catalog.duplicates, isEmpty);
      watch.stop();
      times.add(watch.elapsedMicroseconds);
      final cached = Stopwatch()..start();
      for (var n = 0; n < 100; n++) {
        expect(identical(catalog.duplicates, catalog.duplicates), isTrue);
      }
      cached.stop();
      expect(cached.elapsedMilliseconds, lessThan(100));
    }
    // A regression guard, not a claim about physical Android frame times.
    expect(times.skip(1).reduce(max), lessThan(1000000));
    // ignore: avoid_print
    print(
      '500 recipes / 1000 distinct ingredients catalog+duplicates us: $times',
    );
  });
}
