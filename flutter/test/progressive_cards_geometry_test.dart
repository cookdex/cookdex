import 'dart:convert';
import 'dart:io';

import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/performance/deep_fixture.dart';
import 'recipe_store_test.dart' show summary;

const _epsilon = 1e-6;

Future<void> _loadRealFonts() async {
  final sdk = Platform.environment['FLUTTER_SDK'];
  if (sdk == null || sdk.isEmpty) {
    throw StateError('FLUTTER_SDK is required for real-font card geometry.');
  }
  final roboto = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    roboto.addFont(
      File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  }
  await roboto.load();
  for (final family in ['MaterialSymbolsRounded', 'MaterialSymbolsOutlined']) {
    final font = FontLoader('packages/material_symbols_icons/$family');
    font.addFont(
      rootBundle.load('packages/material_symbols_icons/lib/fonts/$family.ttf'),
    );
    await font.load();
  }
}

RecipeSummary _recipe(int index) => summary(
  Recipe(
    id: '$index',
    favorite: index.isEven,
    revision: 1,
    createdAt: '2026-10-30',
    updatedAt: '2026-10-30',
    fields: scaleRecipeFields(index),
  ),
);

List<RecipeSummary> _geometryRecipes() {
  final path = Platform.environment['CARD_GEOMETRY_FIXTURE'];
  if (path == null || path.isEmpty) return List.generate(2500, _recipe);
  final records = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  expect(records, hasLength(2500));
  return records.map((record) {
    final value = record as Map<String, dynamic>;
    return RecipeSummary(
      id: value['id'] as String,
      title: value['title'] as String,
      description: value['description'] as String,
      ingredients: (value['ingredients'] as List<dynamic>).map((ingredient) {
        if (ingredient is String) return ingredient;
        return (ingredient as Map<String, dynamic>)['name'] as String;
      }).toList(),
      tags: (value['tags'] as List<dynamic>).cast<String>(),
      notes: value['notes'] as String,
      favorite: value['favorite'] as bool,
      createdAt: value['createdAt'] as String,
      updatedAt: value['updatedAt'] as String,
      servings: value['servings'] as String,
      prepTime: value['prepTime'] as String,
      cookTime: value['cookTime'] as String,
      totalTime: value['totalTime'] as String,
      revision: value['revision'] as int,
    );
  }).toList();
}

Widget _host({
  required Widget child,
  double systemScale = 1,
  bool tablet = false,
}) => MaterialApp(
  theme: cookdexTheme(colors: cookdexLightColors, largerBody: tablet),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(systemScale)),
      child: Scaffold(body: child),
    ),
  ),
);

Finder _title(Finder card, RecipeSummary recipe) =>
    find.descendant(of: card, matching: find.text(recipe.title));

void _expectRect(Rect actual, Rect expected, String reason) {
  expect(actual.left, closeTo(expected.left, _epsilon), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, _epsilon), reason: '$reason top');
  expect(
    actual.width,
    closeTo(expected.width, _epsilon),
    reason: '$reason width',
  );
  expect(
    actual.height,
    closeTo(expected.height, _epsilon),
    reason: '$reason height',
  );
}

void main() {
  testWidgets('all 2500 synthetic cards match native layout and shell titles', (
    tester,
  ) async {
    await tester.runAsync(_loadRealFonts);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final recipes = _geometryRecipes();
    // Reuse across configurations to also exercise geometry cache invalidation
    // for changed width, text scaler, theme text metrics, and grid mode.
    final cache = CardGeometryCache();
    var checked = 0;
    for (final config in [
      ('phone390', const Size(390, 844), 358.0, 1.0, false),
      ('largest390', const Size(390, 844), 358.0, 2.0, false),
      ('tablet1280', const Size(1280, 800), 408.0, 1.0, true),
    ]) {
      tester.view.physicalSize = config.$2;
      // Extra large recipe text is a detail/editor preference. RecipesScreen
      // has no RecipeTextScale ancestor, so largest library text uses system2.
      if (config.$5) {
        expect(recipeGridColumns(1248), 3);
        expect((1248 - 2 * 12) / 3, config.$3);
      }
      for (var first = 0; first < recipes.length; first += 25) {
        final batch = recipes.skip(first).take(25).toList();
        final geometries = <String, CardGeometry?>{};
        await tester.pumpWidget(
          _host(
            systemScale: config.$4,
            tablet: config.$5,
            // Layout every native card in a bounded-width pair; no list
            // virtualization, estimated extents, or screenshot clipping can
            // hide a mismatch. Suppress painting of this large layout batch.
            child: Offstage(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                minHeight: 0,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final recipe in batch)
                      Builder(
                        builder: (context) {
                          final fixedHeight = config.$5
                              ? recipeGridCardHeight(context)
                              : null;
                          geometries[recipe.id] = cache.measure(
                            context,
                            recipe,
                            config.$3,
                            grid: config.$5,
                            fixedHeight: fixedHeight,
                          );
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                key: ValueKey('full-${recipe.id}'),
                                width: config.$3,
                                height: fixedHeight,
                                child: recipeCardForTest(
                                  recipe,
                                  grid: config.$5,
                                ),
                              ),
                              SizedBox(
                                key: ValueKey('shell-${recipe.id}'),
                                width: config.$3,
                                height: fixedHeight,
                                child: recipeCardForTest(
                                  recipe,
                                  grid: config.$5,
                                  stage: 0,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '${config.$1} batch $first',
        );
        for (final recipe in batch) {
          final label = '${config.$1} recipe ${recipe.id}';
          final geometry = geometries[recipe.id];
          expect(geometry, isNotNull, reason: '$label known geometry');
          final full = find.byKey(
            ValueKey('full-${recipe.id}'),
            skipOffstage: false,
          );
          final shell = find.byKey(
            ValueKey('shell-${recipe.id}'),
            skipOffstage: false,
          );
          final fullRect = tester.getRect(full);
          final shellRect = tester.getRect(shell);
          expect(
            geometry!.height,
            closeTo(fullRect.height, _epsilon),
            reason: label,
          );
          expect(
            shellRect.height,
            closeTo(fullRect.height, _epsilon),
            reason: label,
          );
          final fullTitle = find.descendant(
            of: full,
            matching: find.text(recipe.title, skipOffstage: false),
            skipOffstage: false,
          );
          final shellTitle = find.descendant(
            of: shell,
            matching: find.text(recipe.title, skipOffstage: false),
            skipOffstage: false,
          );
          expect(fullTitle, findsOneWidget, reason: label);
          expect(shellTitle, findsOneWidget, reason: label);
          final actualTitle = tester.getRect(fullTitle);
          expect(
            geometry.titleHeight,
            closeTo(actualTitle.height, _epsilon),
            reason: label,
          );
          _expectRect(
            tester.getRect(shellTitle).shift(-shellRect.topLeft),
            actualTitle.shift(-fullRect.topLeft),
            '$label shell title',
          );
          checked++;
        }
      }
    }
    expect(checked, 7500);
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('filling shells preserves visible card rects and scroll offset', (
    tester,
  ) async {
    await tester.runAsync(_loadRealFonts);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final stage = ValueNotifier(0);
    final controller = ScrollController();
    final recipes = [
      for (final index in [1, 8, 21]) _recipe(index),
    ];
    await tester.pumpWidget(
      _host(
        child: ValueListenableBuilder<int>(
          valueListenable: stage,
          builder: (context, value, _) => ListView(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const SizedBox(height: 120),
              for (final recipe in recipes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    key: ValueKey('visible-${recipe.id}'),
                    child: recipeCardForTest(recipe, stage: value),
                  ),
                ),
              const SizedBox(height: 800),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.jumpTo(120);
    await tester.pumpAndSettle();
    final before = <String, Rect>{};
    final titles = <String, Rect>{};
    for (final recipe in recipes) {
      final card = find.byKey(ValueKey('visible-${recipe.id}'));
      before[recipe.id] = tester.getRect(card);
      titles[recipe.id] = tester.getRect(_title(card, recipe));
      expect(
        before[recipe.id]!.overlaps(const Rect.fromLTWH(0, 0, 390, 844)),
        isTrue,
      );
    }
    final offset = controller.offset;
    // Check each fill stage as well as the fully populated final card.
    for (var next = 1; next <= 4; next++) {
      stage.value = next;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'stage $next');
      expect(controller.offset, offset, reason: 'stage $next scroll offset');
      for (final recipe in recipes) {
        final card = find.byKey(ValueKey('visible-${recipe.id}'));
        _expectRect(
          tester.getRect(card),
          before[recipe.id]!,
          'stage $next card ${recipe.id}',
        );
        _expectRect(
          tester.getRect(_title(card, recipe)),
          titles[recipe.id]!,
          'stage $next title ${recipe.id}',
        );
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    stage.dispose();
  });
}
