import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'support/polish_fixtures.dart';
import 'editor_test.dart' show reveal;
import 'back_navigation_audit_test.dart' show gesture;

class _RenderRepository extends PolishRepository implements ScalingRepository {
  _RenderRepository() {
    final rows = recipes['0']!.fields.ingredients;
    for (var i = 0; i < rows.length; i++) {
      final old = rows[i];
      rows[i] = Ingredient(
        amount: old.amount,
        unit: i == 0 ? 'lb' : 'cup',
        name: old.name,
        prepNote: i == 1 ? 'finely chopped' : '',
        optional: i == 4,
        section: i < 2
            ? 'Filling'
            : i < 5
            ? 'Sauce'
            : 'Topping',
      );
    }
  }
  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async =>
      [
        for (var i = 0; i < ingredients.length; i++)
          i == 0
              ? '2'
              : i == 2
              ? '1/2–3/4'
              : '1',
      ];
  @override
  Future<ScaledRecipeView> scaleRecipe(RecipeFields fields, int scale) async =>
      ScaledRecipeView(
        quantities: [
          for (var i = 0; i < fields.ingredients.length; i++)
            i == 0
                ? '4 lb'
                : i == 2
                ? '1–1 1/2 cups'
                : '2 cups',
        ],
        servings: '8',
      );
  @override
  Future<ShoppingResult> addShoppingScaled(
    int generation,
    String id,
    List<int> indices,
    int scale,
  ) => throw UnimplementedError();
}

void main() {
  testWidgets('navigation and ingredient polish rendered matrix', (
    tester,
  ) async {
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
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final config in [
        ('small', const Size(320, 800), 1.0),
        ('normal', const Size(390, 844), 1.0),
        ('largest', const Size(390, 844), 2.0),
        ('tablet', const Size(1280, 800), 1.0),
      ]) {
        tester.view.physicalSize = config.$2;
        tester.platformDispatcher.textScaleFactorTestValue = config.$3;
        final prefs = LocalPreferences.memory()
          ..setThemeMode(mode)
          ..setRecipeTextSize(
            config.$3 == 2 ? RecipeTextSize.extraLarge : RecipeTextSize.normal,
          )
          ..setView(RecipeView.compact);
        final repo = _RenderRepository();
        final store = RecipeStore(repo, prefs);
        await store.initialize();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
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
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../artifacts/navigation-polish/screens/${mode.name}-${config.$1}-$name.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await capture('compact-all');
        if (config.$1 == 'small' || config.$1 == 'normal') {
          prefs.setFavoritesOnly(true);
          await tester.pumpAndSettle();
          await capture('compact-favorites');
          prefs.setView(RecipeView.cards);
          await tester.pumpAndSettle();
          await capture('cards-favorites');
          prefs.setFavoritesOnly(false);
          await tester.pumpAndSettle();
          await capture('cards-all');
        }
        await tester.tap(find.text('Family pork supper').first);
        await tester.pumpAndSettle();
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
        expect(
          find.text('4 lb boneless country-style pork ribs'),
          findsOneWidget,
        );
        Future<void> ingredients() async {
          await Scrollable.ensureVisible(
            tester.element(find.text('Filling')),
            alignment: .1,
          );
          await tester.pumpAndSettle();
        }

        await ingredients();
        await capture('recipe-scaled');
        await tester.tap(find.byKey(const Key('cook-toggle')));
        await tester.pumpAndSettle();
        await ingredients();
        await capture('cook-scaled');
        await tester.tap(find.byTooltip('Edit recipe'));
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Filling'));
        await Scrollable.ensureVisible(
          tester.element(find.text('Filling')),
          alignment: .15,
        );
        await tester.pumpAndSettle();
        await capture('editor-sections');
        await reveal(tester, find.text('Sauce'));
        await Scrollable.ensureVisible(
          tester.element(find.text('Sauce')),
          alignment: .25,
        );
        await tester.pumpAndSettle();
        await capture('editor-next-section');
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(RecipeDetail), findsOneWidget);
        await tester.tap(find.text('Shopping list').last);
        await tester.pumpAndSettle();
        await capture('shopping-sources');
        if (config.$1 == 'normal' || config.$1 == 'tablet') {
          await gesture(tester, 'startBackGesture', 0);
          await gesture(tester, 'updateBackGestureProgress', .65);
          await capture('tab-back-preview');
          await gesture(tester, 'cancelBackGesture');
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      }
    }
  }, skip: Platform.environment['NAVIGATION_POLISH_SCREENSHOTS'] != '1');
}
