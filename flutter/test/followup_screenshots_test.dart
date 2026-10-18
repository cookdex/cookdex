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

import 'import_test.dart' show ImportFakeService, ShellPlatform;
import 'support/polish_fixtures.dart';

class ScreenshotPlatform extends ShellPlatform {
  ScreenshotPlatform(this.android);
  final bool android;
  @override
  bool get isAndroid => android;
}

// Keep the historical polish fixture intact. This follow-up matrix includes
// missing descriptions/tags/metadata and wrapped metadata beside normal cards.
class FollowupRepository extends PolishRepository {
  FollowupRepository() {
    for (var i = 1; i < 12; i++) {
      final original = recipes['$i']!;
      final fields = original.fields;
      final variation = i % 5;
      final noMetadata = variation == 2 || variation == 4;
      recipes[original.id] = Recipe(
        id: original.id,
        favorite: original.favorite,
        revision: original.revision,
        createdAt: original.createdAt,
        updatedAt: original.updatedAt,
        fields: RecipeFields(
          title: fields.title,
          description: variation == 1 || variation == 4
              ? ''
              : fields.description,
          servings: noMetadata
              ? ''
              : variation == 3
              ? '4 generous bowls with vegetables and bread'
              : fields.servings,
          prepTime: noMetadata ? '' : fields.prepTime,
          cookTime: noMetadata ? '' : fields.cookTime,
          totalTime: noMetadata
              ? ''
              : variation == 3
              ? '45 min, plus proofing and resting overnight'
              : fields.totalTime,
          source: fields.source,
          tags: variation == 1 || variation == 4 ? [] : fields.tags,
          notes: fields.notes,
          ingredients: fields.ingredients,
          steps: fields.steps,
        ),
      );
    }
  }
}

void main() {
  final phase = Platform.environment['SCREENSHOT_PHASE'] ?? 'after';
  final enabled = Platform.environment['FOLLOWUP_SCREENSHOTS'] == '1';
  testWidgets('all screens across four window sizes with readable screenshots', (
    tester,
  ) async {
    if (!enabled) return;
    final sdk = Platform.environment['FLUTTER_SDK']!;
    await tester.runAsync(() async {
      final loader = FontLoader('Roboto');
      for (final weight in ['regular', 'bold']) {
        loader.addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then((b) => ByteData.sublistView(b)),
        );
      }
      await loader.load();
      final material = FontLoader("MaterialIcons");
      material.addFont(
        File(
          "$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf",
        ).readAsBytes().then((b) => ByteData.sublistView(b)),
      );
      await material.load();
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
    for (final entry in {
      'phone': const Size(390, 844),
      'tablet-portrait': const Size(800, 1280),
      'tablet-landscape': const Size(1280, 800),
      'desktop': const Size(1920, 1080),
    }.entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      final prefs = LocalPreferences.memory();
      final store = RecipeStore(FollowupRepository(), prefs);
      await store.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: CookdexApp(
            store: store,
            platform: ScreenshotPlatform(entry.key != 'desktop'),
            importService: ImportFakeService(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> shot(String screen) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '${entry.key} $screen');
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/polish-round2-followup/$phase/screens/${entry.key}-$screen.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> tap(Finder f) async {
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await shot('recipes-cards');
      prefs.setView(RecipeView.compact);
      await shot('recipes-compact');
      expect(
        tester.getSize(find.byKey(const ValueKey('0')).first).height,
        lessThan(80),
      );
      prefs.setView(RecipeView.cards);
      await tester.pumpAndSettle();
      await tap(find.text('Family pork supper').first);
      expect(find.byType(RecipeDetail), findsOneWidget);
      await shot('recipe');
      await tap(find.text('Cook'));
      await shot('cook');
      await tap(find.byTooltip('Edit recipe'));
      await shot('editor');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(find.text('Shopping list').last);
      await shot('shopping');
      await tap(find.text('Settings').last);
      await shot('settings');
      await tap(find.text('Recipe text size'));
      await shot('appearance');
      await tap(find.text('Extra large'));
      expect(prefs.recipeTextSize, RecipeTextSize.extraLarge);
      await tap(find.text('Recipes').last);
      await shot('recipe-extra-large');
      await tap(find.text('Recipes').last);
      await tap(find.byTooltip('Add recipe'));
      await shot('add');
      await tap(find.text('Smart Import'));
      await shot('import-text');
      await tap(find.text('Link'));
      await shot('import-link');
      await tap(find.text('Photos'));
      await shot('import-photos');
      await tap(find.text('Smart Import settings'));
      await shot('ai-settings');
      await tap(find.text('Cancel').last);
      await tap(find.text('Text'));
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.decoration?.hintText == 'Paste recipe text',
        ),
        'Synthetic family recipe',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await shot('import-candidates');
      await tap(find.text('First recipe'));
      await shot('review-import');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      if (find.text('Discard').evaluate().isNotEmpty) {
        await tap(find.text('Discard'));
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
