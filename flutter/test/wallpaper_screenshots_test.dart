import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/feedback.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakeService, ShellPlatform;
import 'editor_test.dart' show reveal;
import 'support/polish_fixtures.dart';
import 'support/wallpaper_fixture.dart';

class _AndroidPlatform extends ShellPlatform {
  @override
  bool get isAndroid => true;

  @override
  Future<ColorScheme?> wallpaperColorScheme({
    Brightness brightness = Brightness.dark,
  }) async => wallpaperFixture(brightness);
}

// Every row, service and preference is synthetic and memory-only. Never opens
// a native session, owner library, network provider or attached device.
class _Repository extends PolishRepository {
  @override
  CollectionSnapshot get current {
    final source = super.current;
    return CollectionSnapshot(
      setAsideCount: 0,
      generation: source.generation,
      summaries: source.summaries,
      shoppingCategories: const [
        ShoppingCategory(id: 'produce', name: 'Produce'),
        ShoppingCategory(id: 'pantry', name: 'Pantry'),
        ShoppingCategory(id: 'other', name: 'Other'),
      ],
      shopping: [
        for (final (i, item) in source.shopping.indexed)
          ShoppingItem(
            id: item.id,
            categoryId: i < 3
                ? 'produce'
                : i < 6
                ? 'pantry'
                : 'other',
            name: item.name,
            measures: item.measures,
            contributorScales: const [],
            contributorIds: item.contributorIds,
            checked: i == 1,
            quantityText: item.quantityText,
          ),
      ],
      conflicts: const [],
      hasPrevious: false,
    );
  }
}

Future<void> _fonts(WidgetTester tester) async {
  final sdk =
      Platform.environment['FLUTTER_SDK'] ??
      (throw StateError('Set FLUTTER_SDK before running font tests'));
  await tester.runAsync(() async {
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'bold']) {
      roboto.addFont(
        File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await roboto.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
    await icons.load();
    for (final family in [
      'MaterialSymbolsRounded',
      'MaterialSymbolsOutlined',
    ]) {
      final loader = FontLoader('packages/material_symbols_icons/$family');
      loader.addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/$family.ttf',
        ),
      );
      await loader.load();
    }
  });
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final config in [
      ('small', const Size(320, 800), 1.0),
      ('normal', const Size(390, 844), 1.0),
      ('largest', const Size(390, 844), 2.0),
      ('tablet-landscape', const Size(1280, 800), 1.0),
    ]) {
      testWidgets('${mode.name} ${config.$1}: wallpaper screenshots', (
        tester,
      ) async {
        await _fonts(tester);
        tester.view.physicalSize = config.$2;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        tester.platformDispatcher.textScaleFactorTestValue = config.$3;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.view.resetPadding();
          tester.view.resetViewPadding();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        });
        final prefs = LocalPreferences.memory()
          ..themeMode = mode
          ..setWallpaperColors(true);
        if (config.$1 == 'largest') {
          prefs.setRecipeTextSize(RecipeTextSize.extraLarge);
        }
        final store = RecipeStore(_Repository(), prefs);
        await store.initialize();
        final imports = ImportFakeService();
        final first = imports.result.candidates.first;
        imports.result = ImportDiscovery(
          candidates: [
            Candidate(
              recipe: first.recipe,
              warnings: const ['Check the ingredient amounts before saving.'],
              ingredientSources: const [],
            ),
            imports.result.candidates.last,
          ],
        );
        Widget capture(Widget child) =>
            RepaintBoundary(key: const Key('wallpaper-capture'), child: child);
        await tester.pumpWidget(
          capture(
            CookdexApp(
              store: store,
              platform: _AndroidPlatform(),
              importService: imports,
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> shot(String screen) async {
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '${mode.name} ${config.$1} $screen',
          );
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('wallpaper-capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../artifacts/wallpaper-colors/screens/'
              '${mode.name}-${config.$1}-$screen.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        Future<void> tap(Finder finder) async {
          if (finder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(finder, 300);
          }
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        await shot('recipes-cards-all');
        if (['small', 'normal'].contains(config.$1)) {
          prefs.setFavoritesOnly(true);
          await shot('recipes-cards-favorites');
          prefs.setView(RecipeView.compact);
          await shot('recipes-compact-favorites');
          prefs.setFavoritesOnly(false);
          await shot('recipes-compact-all');
          prefs.setView(RecipeView.cards);
          await tester.pumpAndSettle();
        }
        await tap(find.text('Family pork supper').first);
        await shot('recipe');
        await tap(find.byTooltip('Edit recipe'));
        final draft = tester
            .widget<RecipeEditor>(find.byType(RecipeEditor))
            .controller
            .draft;
        final ingredient = draft.sections.first.rows.first;
        final ingredientName = find.byKey(ValueKey('${ingredient.id}-name'));
        await reveal(tester, ingredientName);
        // Position the whole row consistently for an idle/active comparison.
        await Scrollable.ensureVisible(
          tester.element(find.byKey(ValueKey(ingredient.id))),
          alignment: 0.15,
        );
        await tester.pumpAndSettle();
        await tester.tap(ingredientName);
        await shot('editor-ingredient-active');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tap(find.byTooltip('Back'));
        await tap(find.text('Shopping list').last);
        await shot('shopping-categories');
        await tap(find.text('Settings').last);
        if (find.text('Appearance').evaluate().isEmpty) {
          await tester.scrollUntilVisible(find.text('Appearance'), 300);
        }
        await Scrollable.ensureVisible(
          tester.element(find.text('Appearance')),
          alignment: 0,
        );
        await shot('settings-appearance');
        if (config.$1 == 'normal') {
          await tap(find.text('Recipes').last);
          await tap(find.text('Recipes').last);
          await tap(find.byTooltip('Add recipe'));
          await tap(find.text('Smart Import'));
          await tester.enterText(
            find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText == 'Paste recipe text',
            ),
            'Synthetic family recipe',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await tap(find.widgetWithText(FilledButton, 'Smart Import'));
          await tap(find.text('First recipe'));
          await shot('import-review-warning');

          showFeedback(
            tester.element(find.byType(Scaffold).last),
            'Could not import. Check the recipe and try again.',
            kind: FeedbackKind.error,
          );
          await shot('import-feedback');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      }, skip: Platform.environment['WALLPAPER_SCREENSHOTS'] != '1');
    }
  }
}
