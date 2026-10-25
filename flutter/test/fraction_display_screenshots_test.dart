import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/fraction_display.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart'
    show ShellPlatform, ImportFakeService, ImportRepositoryFake;
import 'recipe_store_test.dart' show summary;

// Entirely synthetic display specimens. The fake returns ordinary core text;
// only the real widgets under review perform the display conversion.
const _names = ['oats', 'yogurt', 'berries', 'nutmeg', 'milk'];
const _amounts = ['1/2', '1 1/4', '1/3–2/3', '3/16', '2 3/4'];
const _doubled = [
  '1 cup',
  '2 1/2 cups',
  '2/3–1 1/3 cups',
  '3/8 tsp',
  '5 1/2 cups',
];

Recipe _specimen() => Recipe(
  id: 'fraction-specimen',
  favorite: false,
  revision: 1,
  createdAt: '2026-10-24',
  updatedAt: '2026-10-24',
  fields: RecipeFields(
    title: 'Morning bowl',
    description: '',
    servings: '4',
    prepTime: '',
    cookTime: '',
    totalTime: '',
    source: '',
    tags: const [],
    notes: '',
    ingredients: [
      for (var i = 0; i < _names.length; i++)
        Ingredient(
          amount: const [
            Amount.rational(numerator: 1, denominator: 2),
            Amount.rational(numerator: 5, denominator: 4),
            Amount.range(
              lowerNumerator: 1,
              lowerDenominator: 3,
              upperNumerator: 2,
              upperDenominator: 3,
            ),
            Amount.rational(numerator: 3, denominator: 16),
            Amount.rational(numerator: 11, denominator: 4),
          ][i],
          unit: i == 3 ? 'tsp' : 'cup',
          name: _names[i],
          prepNote: '',
          optional: false,
          section: 'Bowl',
        ),
    ],
    steps: const [
      'Stir the oats and yogurt together.',
      'Fold in the berries, nutmeg and milk. Serve in bowls.',
    ],
  ),
);

class _FractionRepository extends ImportRepositoryFake
    implements ScalingRepository {
  _FractionRepository() : super([_specimen()]);

  @override
  CollectionSnapshot get current => CollectionSnapshot(
    generation: generation,
    setAsideCount: 0,
    summaries: recipes.values.map(summary).toList(),
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    shopping: [
      for (var i = 0; i < _names.length; i++)
        ShoppingItem(
          categoryId: 'other',
          id: 'fraction-item-$i',
          name: _names[i],
          measures: const [],
          contributorScales: const [],
          contributorIds: const ['fraction-specimen'],
          checked: false,
          quantityText: '${_amounts[i]} ${i == 3 ? 'tsp' : 'cups'}',
        ),
    ],
    conflicts: const [],
    hasPrevious: false,
  );

  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async =>
      _amounts;

  @override
  Future<ScaledRecipeView> scaleRecipe(RecipeFields fields, int scale) async {
    // This fixture exercises the real scale control at 2×. Core arithmetic is
    // covered separately; these are its expected, unmodified text results.
    expect(scale, 4);
    return ScaledRecipeView(quantities: _doubled, servings: '8');
  }

  @override
  Future<ShoppingResult> addShoppingScaled(
    int generation,
    String id,
    List<int> indices,
    int scale,
  ) => throw UnimplementedError();
}

void main() {
  testWidgets(
    'read-only fractions retain plain storage and spoken mixed numbers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final prefs = LocalPreferences.memory();
      final repo = _FractionRepository();
      final store = RecipeStore(repo, prefs);
      await store.initialize();
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: ShellPlatform(),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning bowl').first);
      await tester.pumpAndSettle();
      final label = tester.widget<Text>(find.text('1 and 1/4 cups yogurt'));
      expect(
        label.textSpan!.toPlainText(includeSemanticsLabels: false),
        '1¼ cups yogurt',
      );
      expect(
        find.bySemanticsLabel(RegExp('1 and 1/4 cups yogurt')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('recipe-scale-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recipe-scale-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cook-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('2 and 1/2 cups yogurt')),
        findsOneWidget,
      );
      final scaled = tester.widget<Text>(
        find.text('2/3 to 1 and 1/3 cups berries'),
      );
      expect(
        scaled.textSpan!.toPlainText(includeSemanticsLabels: false),
        '⅔–1⅓ cups berries',
      );
      await tester.tap(find.text('Shopping list').last);
      await tester.pumpAndSettle();
      final shopping = tester.widget<Text>(
        find.byKey(const ValueKey('shopping-item-label-fraction-item-1')),
      );
      expect(
        shopping.textSpan!.toPlainText(includeSemanticsLabels: false),
        '1¼ cups yogurt',
      );
      expect(
        find.bySemanticsLabel(RegExp('1 and 1/4 cups yogurt')),
        findsOneWidget,
      );
      expect(store.shopping[1].quantityText, '1 1/4 cups');
      expect(
        await repo.ingredientAmounts(
          repo.recipes.values.first.fields.ingredients,
        ),
        _amounts,
      );
      expect(
        repo.recipes.values.first.fields.ingredients[1].amount,
        const Amount.rational(numerator: 5, denominator: 4),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    semantics.dispose();
    },
  );
  testWidgets('fraction display rendered matrix', (tester) async {
    final sdk = Platform.environment['FLUTTER_SDK']!;
    await tester.runAsync(() async {
      final font = FontLoader('Roboto');
      for (final weight in ['regular', 'medium', 'bold']) {
        font.addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await font.load();
      final amounts = FontLoader('CookdexAmounts');
      amounts.addFont(rootBundle.load('assets/fonts/NotoSans-Medium.ttf'));
      await amounts.load();
      for (final family in [
        'MaterialSymbolsRounded',
        'MaterialSymbolsOutlined',
      ]) {
        final symbols = FontLoader('packages/material_symbols_icons/$family');
        symbols.addFont(
          rootBundle.load(
            'packages/material_symbols_icons/lib/fonts/$family.ttf',
          ),
        );
        await symbols.load();
      }
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    // 32 main renders plus 8 lower-ingredient views at largest text = 40.
    // The normal phone uses Large recipe text, so all three text sizes appear.
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final config in [
        ('small', const Size(320, 800), 1.0, RecipeTextSize.normal),
        ('normal-large', const Size(390, 844), 1.0, RecipeTextSize.large),
        ('largest', const Size(390, 844), 2.0, RecipeTextSize.extraLarge),
        ('tablet', const Size(1280, 800), 1.0, RecipeTextSize.normal),
      ]) {
        tester.view.physicalSize = config.$2;
        tester.platformDispatcher.textScaleFactorTestValue = config.$3;
        final prefs = LocalPreferences.memory()
          ..setThemeMode(mode)
          ..setRecipeTextSize(config.$4)
          ..setView(RecipeView.compact);
        final store = RecipeStore(_FractionRepository(), prefs);
        await store.initialize();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('fraction-capture'),
            child: CookdexApp(
              store: store,
              platform: ShellPlatform(),
              importService: ImportFakeService(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<void> capture(String name) async {
          expect(
            tester.takeException(),
            isNull,
            reason: '${mode.name}/${config.$1}/$name',
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('fraction-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../artifacts/smart-import-183-finish/screens/'
              '${mode.name}-${config.$1}-$name.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        Future<void> ingredientView(String name) async {
          await Scrollable.ensureVisible(
            tester.element(find.text('Bowl')),
            alignment: .05,
          );
          await tester.pumpAndSettle();
          await capture(name);
          if (config.$1 == 'largest') {
            await Scrollable.ensureVisible(
              tester.element(
                find.textContaining('milk', findRichText: true).first,
              ),
              alignment: .75,
            );
            await tester.pumpAndSettle();
            await capture('$name-lower');
          }
        }

        await tester.tap(find.text('Morning bowl').first);
        await tester.pumpAndSettle();
        await ingredientView('detail');
        await tester.ensureVisible(
          find.byKey(const Key('recipe-scale-toggle')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('recipe-scale-toggle')));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byKey(const Key('recipe-scale-4')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('recipe-scale-4')));
        await tester.pumpAndSettle();
        await ingredientView('detail-scaled');
        await tester.tap(find.byKey(const Key('cook-toggle')));
        await tester.pumpAndSettle();
        await ingredientView('cook-scaled');
        await tester.tap(find.text('Shopping list').last);
        await tester.pumpAndSettle();
        await capture('shopping');
        if (config.$1 == 'largest') {
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('fraction-item-4')),
            180,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          await capture('shopping-lower');
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      }
    }
    // Inspect every emitted glyph, including the rarer fifths, sixths and tenths,
    // in the same medium face at all three reading sizes and enlarged OS text.
    tester.view.physicalSize = const Size(1200, 650);
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: const Key('all-fractions'),
          child: Material(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final size in [16.0, 18.0, 20.0, 40.0]) ...[
                  Text(
                    '½ ⅓ ⅔ ¼ ¾ ⅕ ⅖ ⅗ ⅘ ⅙ ⅚ ⅐ ⅛ ⅜ ⅝ ⅞ ⅑ ⅒',
                    style: amountDisplayStyle.copyWith(fontSize: size),
                  ),
                  Text(
                    '1½ 1⅓ 1⅔ 1¼ 1¾ 1⅕ 1⅖ 1⅗ 1⅘ 1⅙ 1⅚ 1⅐ 1⅛ 1⅜ 1⅝ 1⅞ 1⅑ 1⅒',
                    style: amountDisplayStyle.copyWith(fontSize: size),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('all-fractions')),
      );
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '../artifacts/smart-import-183-finish/screens/all-fractions.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
  }, skip: Platform.environment['FRACTION_SCREENSHOTS'] != '1');
}
