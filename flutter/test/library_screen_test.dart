import 'package:cookdex/editor_model.dart';
import 'package:cookdex/library_catalog.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;
import 'import_test.dart' show ShellPlatform, ImportFakeService;

List<Recipe> libraryFixtures() => [
  for (var i = 0; i < 16; i++)
    recipeFromJson(
      recipeToJson(recipe('library-$i'))
        ..['fields'] = {
          ...recipeToJson(recipe('library-$i'))['fields']
              as Map<String, dynamic>,
          'title': [
            'Baked garden pasta',
            'Creamy mushroom risotto',
            'Lemon herb orzo',
            'Roasted pepper tart',
            'Spinach stuffed shells',
            'Summer tomato gratin',
            'Weeknight gnocchi',
            'Zucchini ribbons',
          ][i % 8],
          'tags': [i < 8 ? 'weeknight' : 'Weeknight', 'vegetarian'],
          'ingredients': [
            {
              'name': i < 8
                  ? 'parmesan cheese'
                  : i < 14
                  ? 'parm'
                  : 'Parm.',
              'amount': {'kind': 'rational', 'numerator': 1, 'denominator': 2},
              'unit': 'cup',
              'prepNote': 'finely grated',
              'optional': false,
              'section': '',
            },
            for (final name in [
              'Butter',
              'Egg',
              'Eggs',
              'Garlic',
              'Olive oil',
              'Salt',
            ])
              {
                'name': name,
                'amount': {'kind': 'unspecified'},
                'unit': '',
                'prepNote': '',
                'optional': false,
                'section': '',
              },
          ],
        },
    ),
];

List<Recipe> libraryFeedbackFixtures() => [
  for (final (i, original) in libraryFixtures().indexed)
    recipeFromJson(() {
      final json = recipeToJson(original);
      final fields = json['fields'] as Map<String, dynamic>;
      final rows = List<dynamic>.from(fields['ingredients'] as List);
      fields['ingredients'] = rows;
      if (i == 15) rows[0]['name'] = 'Parm';
      for (final row in rows) {
        if (['Butter', 'Garlic', 'Olive oil', 'Salt'].contains(row['name']) &&
            i.isEven) {
          row['name'] = (row['name'] as String).toLowerCase();
        }
      }
      rows.add({
        ...rows[1] as Map<String, dynamic>,
        'name': i.isEven ? 'black pepper' : 'Black pepper',
      });
      return json;
    }()),
];

Recipe overlappingLibraryFixture() => recipeFromJson(() {
  final json = recipeToJson(libraryFixtures().first);
  final fields = json['fields'] as Map<String, dynamic>;
  fields['title'] = 'Egg bake with topping';
  fields['tags'] = ['Weeknight', 'vegetarian', 'weeknight'];
  fields['ingredients'] = [
    for (final (name, amount, section) in [
      ('Eggs', 2, 'Filling'),
      ('Egg', 1, 'Filling'),
      ('Eggs', 3, 'Topping'),
    ])
      {
        'name': name,
        'amount': {'kind': 'rational', 'numerator': amount, 'denominator': 1},
        'unit': '',
        'prepNote': 'beaten',
        'optional': section == 'Topping',
        'section': section,
      },
  ];
  return json;
}());

class LibraryFakeRepository extends FakeRepository
    implements LibraryRepository {
  LibraryFakeRepository(super.recipes);
  int changes = 0, undos = 0;
  @override
  Future<LibraryChangeResult> addLibraryTag(
    int expected,
    List<String> ids,
    String tag,
  ) async {
    if (expected != generation) throw StateError('Changed');
    final before = <Recipe>[];
    for (final id in ids) {
      final recipe = recipes[id]!;
      if (recipe.fields.tags.contains(tag)) continue;
      before.add(recipe);
      final json = recipeToJson(recipe);
      (json['fields'] as Map<String, dynamic>)['tags'] = [
        ...recipe.fields.tags,
        tag,
      ];
      json['revision'] = recipe.revision + 1;
      recipes[id] = recipeFromJson(json);
    }
    generation++;
    changes++;
    return LibraryChangeResult(current, before, before.length);
  }

  @override
  Future<List<String>> ingredientAmounts(
    List<Ingredient> ingredients,
  ) async => [
    for (final i in ingredients)
      if (i.amount case Amount_Rational(:final numerator, :final denominator))
        denominator == 1 ? '$numerator' : '$numerator/$denominator'
      else
        '',
  ];
  @override
  Future<LibraryChangeResult> changeLibraryNames(
    int expected,
    bool tags,
    List<String> sources,
    String? target,
  ) async {
    if (generation != expected) throw StateError('Changed');
    final before = <Recipe>[];
    for (final recipe in recipes.values.toList()) {
      final names = tags
          ? recipe.fields.tags
          : recipe.fields.ingredients.map((i) => i.name);
      if (!names.any(sources.contains)) continue;
      before.add(recipe);
      final json = recipeToJson(recipe);
      final fields = json['fields'] as Map<String, dynamic>;
      if (tags) {
        fields['tags'] = {
          for (final name in recipe.fields.tags)
            if (!sources.contains(name)) name else ?target,
        }.toList();
      } else {
        for (final row in fields['ingredients'] as List) {
          if (sources.contains(row['name'])) row['name'] = target;
        }
      }
      json['revision'] = recipe.revision + 1;
      recipes[recipe.id] = recipeFromJson(json);
    }
    generation++;
    changes++;
    return LibraryChangeResult(current, before, before.length);
  }

  @override
  Future<CollectionSnapshot> undoLibraryNames(int expected, Object undo) async {
    if (generation != expected) throw StateError('Changed');
    for (final before in undo as List<Recipe>) {
      recipes[before.id] = recipeFromJson(
        recipeToJson(before)..['revision'] = recipes[before.id]!.revision + 1,
      );
    }
    generation++;
    undos++;
    return current;
  }
}

Future<(RecipeStore, LibraryFakeRepository, LocalPreferences)> libraryHarness(
  WidgetTester tester, {
  bool dark = false,
  List<Recipe>? recipes,
}) async {
  final prefs = LocalPreferences.memory();
  final repo = LibraryFakeRepository(recipes ?? libraryFixtures());
  final store = RecipeStore(repo, prefs);
  await store.initialize();
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(colors: dark ? cookdexColors : cookdexLightColors),
      home: LibraryScreen(
        store: store,
        onOpenRecipe: (context, id) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Recipe')),
              body: Text(id),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (store, repo, prefs);
}

void main() {
  testWidgets('Cancel every Library name dialog and picker without a batch', (
    tester,
  ) async {
    final (store, repo, prefs) = await libraryHarness(tester);
    final generation = store.generation;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    });
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('parm').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'a new name');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge into…'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge into…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'parmesan cheese');
    await tester.pumpAndSettle();
    await tester.tap(find.text('parmesan cheese').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.changes, 0);
    expect(repo.undos, 0);
    expect(store.generation, generation);
    expect(tester.takeException(), isNull);
  });

  test('Duplicate keeper ties prefer less punctuation, then lowercase', () {
    final repo = LibraryFakeRepository(libraryFeedbackFixtures());
    final catalog = LibraryCatalog(
      repo.current.summaries,
      LibraryKind.ingredients,
    );
    expect(catalog.duplicates, hasLength(6));
    expect(catalog.duplicates.first.map((n) => n.name), [
      'black pepper',
      'Black pepper',
    ]);
    expect(
      catalog.duplicates
          .firstWhere((g) => g.first.name == 'parm')
          .map((n) => n.name),
      ['parm', 'Parm', 'Parm.'],
    );
    expect(libraryNumberWarning(['Eggs'], 'Egg'), contains('“2 Egg”'));
    expect(libraryNumberWarning(['Egg'], 'Eggs'), contains('“1 Eggs”'));
    expect(singularPluralLibraryNames('Parm.', 'parm'), isFalse);
  });

  testWidgets(
    'Six duplicate groups stay bounded and keeper choice updates affected recipes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, repo, prefs) = await libraryHarness(
        tester,
        recipes: libraryFeedbackFixtures(),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      expect(
        tester.getSize(find.byKey(const Key('library-duplicates-card'))).height,
        lessThanOrEqualTo(422),
      );
      await tester.tap(find.text('Show all (6)'));
      await tester.pumpAndSettle();
      final group = find.ancestor(
        of: find.text('Parm.'),
        matching: find.byType(Card),
      );
      await tester.ensureVisible(
        find.descendant(of: group, matching: find.text('Merge')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: group, matching: find.text('Merge')),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<RadioGroup<LibraryName>>(
              find.byType(RadioGroup<LibraryName>),
            )
            .groupValue!
            .name,
        'parm',
      );
      expect(find.text('1/2 cup Parm., finely grated'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(RadioListTile<LibraryName>, 'Parm.'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Merge “parm” (6 recipes), “Parm” (1 recipe) into “Parm.” (1 recipe)?',
        ),
        findsOneWidget,
      );
      expect(find.text('1/2 cup Parm., finely grated'), findsNothing);
      expect(find.text('1/2 cup parm, finely grated'), findsWidgets);
      expect(find.text('and 2 more'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Merge').last);
      await tester.pumpAndSettle();
      expect(repo.changes, 1);
      expect(
        store.summaries.where((r) => r.ingredients.contains('Parm.')),
        hasLength(8),
      );
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 10),
      );
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        LibraryCatalog(store.summaries, LibraryKind.ingredients).duplicates,
        hasLength(6),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Plural merges count overlapping recipes once and preserve all rows through Undo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = overlappingLibraryFixture();
      final (store, repo, prefs) = await libraryHarness(
        tester,
        recipes: [original],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      final catalog = LibraryCatalog(store.summaries, LibraryKind.ingredients);
      expect(catalog.named('Eggs')!.count, 1);
      expect(catalog.duplicates, isEmpty);
      await tester.tap(find.text('Eggs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge into…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Egg'));
      await tester.pumpAndSettle();
      expect(find.textContaining('for example “2 Egg”'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('2 Eggs, beaten\n3 Eggs, beaten (optional)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(original.fields.title),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      expect(find.text('Merged in 1 recipe'), findsOneWidget);
      expect(repo.recipes[original.id]!.fields.ingredients, hasLength(3));
      expect(
        repo.recipes[original.id]!.fields.ingredients.map((i) => i.section),
        ['Filling', 'Filling', 'Topping'],
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        recipeToJson(repo.recipes[original.id]!)['fields'],
        recipeToJson(original)['fields'],
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Egg'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Eggs');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('for example “1 Eggs”'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.changes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Windows context menu anchors at the pointer and acts on its row, not selected detail',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, repo, prefs) = await libraryHarness(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('weeknight').first);
      await tester.pumpAndSettle();
      for (final compact in [true, false]) {
        final row = find.byKey(
          ValueKey(('library-name', compact, 'weeknight')),
        );
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(tester.widget<ListTile>(row).selected, isTrue);
        final material = tester.widget<Material>(
          find.ancestor(of: row, matching: find.byType(Material)).first,
        );
        expect(
          material.color,
          Theme.of(tester.element(row)).colorScheme.primaryContainer,
        );
      }
      final detailRecipe = find.text('Baked garden pasta');
      expect(
        tester
            .getSize(
              find.ancestor(of: detailRecipe, matching: find.byType(Card)),
            )
            .width,
        greaterThan(1000),
      );
      final row = find.byKey(
        const ValueKey(('library-name', false, 'Weeknight')),
      );
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final point = tester.getTopLeft(row) + const Offset(130, 24);
      final mouse = await tester.startGesture(
        point,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.up();
      await tester.pumpAndSettle();
      final menu = tester.getRect(
        find
            .ancestor(
              of: find.widgetWithText(PopupMenuItem<String>, 'Rename'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect((menu.left - point.dx).abs(), lessThan(12));
      expect((menu.top - point.dy).abs(), lessThan(12));
      await tester.tap(
        find.widgetWithText(PopupMenuItem<String>, 'Remove tag'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Remove “Weeknight” from 8 recipes?\n\nYour recipes won\'t be deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(TextButton, 'Remove tag').last);
      await tester.pumpAndSettle();
      expect(
        LibraryCatalog(
          store.summaries,
          LibraryKind.tags,
        ).named('weeknight')!.count,
        8,
      );
      expect(
        LibraryCatalog(store.summaries, LibraryKind.tags).named('Weeknight'),
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Settings Library opens recipes and Back returns to name details',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final prefs = LocalPreferences.memory();
      final repo = LibraryFakeRepository(libraryFixtures());
      final store = RecipeStore(repo, prefs);
      await store.initialize();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: ShellPlatform(),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Tidy up ingredient names and tags'), findsOneWidget);
      await tester.tap(find.text('Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('parm').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Baked garden pasta'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Recipe actions'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to Library'));
      await tester.pumpAndSettle();
      expect(find.text('Show all (6)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Rename, tag removal, duplicate merge and Undo return whole batches',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, repo, prefs) = await libraryHarness(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Merge').last);
      await tester.pumpAndSettle();
      expect(find.text('Possible duplicates'), findsNothing);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Possible duplicates'), findsOneWidget);
      await tester.tap(find.text('parm').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Rename in 6 recipes.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'aged parmesan');
      await tester.pumpAndSettle();
      expect(find.text('Rename in 6 recipes.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.text('Renamed in 6 recipes'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('parm'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tags'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('weeknight').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.changes, 2);
      await tester.tap(find.text('Remove tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Remove tag').last);
      await tester.pumpAndSettle();
      expect(find.text('Removed tag from 8 recipes'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        LibraryCatalog(
          store.summaries,
          LibraryKind.tags,
        ).named('weeknight')!.count,
        8,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Library counts exact names and duplicate groups keep plurals separate',
    () {
      final repo = LibraryFakeRepository(libraryFixtures());
      final catalog = LibraryCatalog(
        repo.current.summaries,
        LibraryKind.ingredients,
      );
      expect(catalog.named('parm')!.count, 6);
      expect(catalog.duplicates.single.map((n) => n.name), ['parm', 'Parm.']);
      expect(catalog.named('Egg'), isNotNull);
      expect(catalog.named('Eggs'), isNotNull);
      expect(similarLibraryName('Egg', 'Eggs'), isTrue);
      expect(similarLibraryName('tomato', 'tomatoes'), isTrue);
    },
  );
  testWidgets(
    'Library checkpoint merges changing recipes only and undoes one batch',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final (store, repo, prefs) = await libraryHarness(tester);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      });
      await tester.tap(find.text('parm').first);
      await tester.pumpAndSettle();
      expect(find.text('Show all (6)'), findsOneWidget);
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'parmesan cheese');
      await tester.pumpAndSettle();
      expect(
        find.text(
          "This matches “parmesan cheese” (8 recipes), so they'll be merged.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('and 1 more'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('1/2 cup parm, finely grated'),
        ),
        findsNWidgets(5),
      );
      expect(find.text('1/2 cup parmesan cheese, finely grated'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.changes, 0);
      await tester.tap(find.text('Merge into…'));
      await tester.pumpAndSettle();
      expect(find.text('Similar names'), findsOneWidget);
      await tester.tap(find.text('parmesan cheese'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      expect(repo.changes, 1);
      expect(find.text('Merged in 6 recipes'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.undos, 1);
      expect(
        LibraryCatalog(
          store.summaries,
          LibraryKind.ingredients,
        ).named('parm')!.count,
        6,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
