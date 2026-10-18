import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/recipe_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show reveal;
import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'support/polish_fixtures.dart';

class _TidyRepository extends PolishRepository {
  _TidyRepository({required bool yieldDetail}) {
    recipes.clear();
    const titles = [
      'Garden supper',
      'Lemon and herb flatbreads with roasted garden vegetables',
      'Soup',
      'Slow roasted tomato and white bean casserole with a crisp herb topping',
      'Cinnamon rolls',
      'Berry preserve for a long weekend breakfast',
      'Crisp potato cakes',
      'Summer salad',
    ];
    const yields = [
      'Serves 4-6',
      'Makes 12 flatbreads',
      '6 servings',
      'Makes 2 large dishes',
      'Makes 18 rolls',
      'Makes 6 jars (250 ml each)',
      '4',
      'Serves 2–3',
    ];
    for (var i = 0; i < titles.length; i++) {
      final data = recipeToJson(polishRecipe('$i', titles[i]));
      data['favorite'] = i.isEven;
      final fields = data['fields'] as Map<String, dynamic>;
      fields['servings'] = i == 0 && yieldDetail
          ? 'Makes 12 vegetable patties'
          : yields[i];
      fields['description'] = switch (i % 4) {
        0 => 'A simple supper with fresh herbs.',
        1 => 'Golden and fragrant, with a soft center and crisp edges. Serve warm with colorful vegetables and a little lemon.',
        2 => '',
        _ => 'A slow weekend favorite with enough for tomorrow.',
      };
      fields['tags'] = switch (i % 4) {
        0 => [
          'Dinner',
          'Family favorites',
          'Vegetarian',
          'Weekend',
          'Quick',
          'Make ahead',
          'Garden vegetables',
        ],
        1 => ['Baking'],
        2 => <String>[],
        _ => ['Make ahead', 'Comfort food', 'Garden vegetables'],
      };
      fields['totalTime'] = i == 5 ? '1 hour plus overnight cooling' : '45 min';
      recipes['$i'] = recipeFromJson(data);
    }
  }
}

void main() {
  testWidgets('ingredient and card tidy rendered matrix', (tester) async {
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
        ('small-phone', const Size(320, 800), 1.0),
        ('normal-phone', const Size(390, 844), 1.0),
        ('largest-phone', const Size(390, 844), 2.0),
        ('tablet-landscape', const Size(1280, 800), 1.0),
        ('tablet-portrait', const Size(800, 1280), 1.0),
        ('desktop', const Size(1440, 900), 1.0),
      ]) {
        tester.view.physicalSize = config.$2;
        tester.platformDispatcher.textScaleFactorTestValue = config.$3;
        final prefs = LocalPreferences.memory()
          ..setThemeMode(mode)
          ..setRecipeTextSize(
            config.$3 == 2 ? RecipeTextSize.extraLarge : RecipeTextSize.normal,
          )
          ..setView(RecipeView.cards);
        final store = RecipeStore(
          _TidyRepository(yieldDetail: mode == ThemeMode.dark),
          prefs,
        );
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
          expect(tester.takeException(), isNull, reason: '${config.$1} $name');
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../artifacts/ingredient-card-tidy/screens/${mode.name}-${config.$1}-$name.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        final phoneRegression =
            config.$1 == 'small-phone' || config.$1 == 'normal-phone';
        if (phoneRegression) {
          await capture('cards-all');
          prefs.setFavoritesOnly(true);
          await tester.pumpAndSettle();
          await capture('cards-favorites');
          prefs.setView(RecipeView.compact);
          await tester.pumpAndSettle();
          await capture('compact-favorites');
          prefs.setFavoritesOnly(false);
          await tester.pumpAndSettle();
          await capture('compact-all');
        } else if (config.$2.width >= 800) {
          await capture('grid-varied-recipes');
        }

        if (config.$1 != 'tablet-portrait' && config.$1 != 'desktop') {
          await tester.tap(find.text('Garden supper').first);
          await tester.pumpAndSettle();
          final metadata = find.byType(RecipeMetadata).last;
          await Scrollable.ensureVisible(
            tester.element(metadata),
            alignment: .25,
          );
          await tester.pumpAndSettle();
          await capture(
            mode == ThemeMode.light
                ? 'detail-servings-range'
                : 'detail-item-yield',
          );
          await tester.tap(find.byTooltip('Edit recipe'));
          await tester.pumpAndSettle();
          final makes = find.byKey(const ValueKey('field-servings'));
          await reveal(tester, makes);
          await Scrollable.ensureVisible(tester.element(makes), alignment: .3);
          await tester.pumpAndSettle();
          await capture('editor-makes-field');
          final editor = tester.widget<RecipeEditor>(find.byType(RecipeEditor));
          editor.controller.draft.servings = '';
          editor.controller.changed();
          await tester.pumpAndSettle();
          await Scrollable.ensureVisible(tester.element(makes), alignment: .3);
          await tester.pumpAndSettle();
          await capture('editor-makes-empty-hint');
          unawaited(
            showDialog<Set<int>>(
              context: tester.element(find.byType(RecipeEditor)),
              barrierDismissible: false,
              builder: (_) => const NameMatchReview(
                matches: [
                  NameMatch(0, false, 'chili-powder.', 'Chili powder'),
                  NameMatch(
                    1,
                    false,
                    'Extra virgin olive oil.',
                    'Extra virgin olive oil',
                  ),
                  NameMatch(0, true, 'family-favorites', 'Family favorites'),
                ],
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('name-match-0')));
          await tester.pumpAndSettle();
          await capture('name-review-mixed-selection');
        }

        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      }
    }
  }, skip: Platform.environment['TIDY_SCREENSHOTS'] != '1');
}
