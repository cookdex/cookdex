import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/components.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/text_import_review.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakeService, ImportRepositoryFake;
import 'recipe_store_test.dart' show recipe;

void main() {
  testWidgets('sharing and text import rendered matrix', (tester) async {
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
    final manifest = <String>[];
    for (final dark in [false, true]) {
      for (final config in [
        ('small-phone', const Size(320, 800), 1.0),
        ('normal-phone', const Size(390, 844), 1.0),
        ('largest-phone', const Size(390, 844), 2.0),
        ('tablet-landscape', const Size(1280, 800), 1.0),
        ('desktop', const Size(1440, 900), 1.0),
      ]) {
        tester.view.physicalSize = config.$2;
        tester.platformDispatcher.textScaleFactorTestValue = config.$3;
        final preferences = LocalPreferences.memory()
          ..setRecipeTextSize(
            config.$3 == 2 ? RecipeTextSize.extraLarge : RecipeTextSize.normal,
          );
        final existing = recipe(
          'one',
          title: 'Lemon and herb flatbreads with roasted garden vegetables',
          favorite: true,
        );
        final repository = ImportRepositoryFake([
          existing,
          recipe('two', title: 'Garden soup'),
          recipe('three', title: 'Cinnamon rolls', favorite: true),
          recipe('four', title: 'Slow roasted tomato and white bean casserole'),
          recipe('five', title: 'Summer salad', favorite: true),
        ]);
        final store = RecipeStore(repository, preferences);
        await store.initialize();
        Set<String>? selection = {'one', 'two'};
        Widget list() => Scaffold(
          body: StatefulBuilder(
            builder: (context, update) => RecipesScreen(
              store: store,
              preferences: preferences,
              selectedIds: selection,
              onToggleSelection: (id) => update(() {
                selection!.contains(id)
                    ? selection!.remove(id)
                    : selection!.add(id);
              }),
              onCloseSelection: () => update(() => selection = null),
              onSelectAll: () {},
              onShareSelection: () {},
              onShoppingSelection: () {},
              onOpenRecipe: (_) {},
              onAdd: () {},
              onActions: (summary) => showRecipeActions(
                context: context,
                store: store,
                recipe: summary,
              ),
            ),
          ),
        );
        Future<void> mount(Widget child) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: MaterialApp(
                theme: cookdexTheme(
                  colors: dark ? cookdexColors : cookdexLightColors,
                ),
                home: child,
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> capture(String state) async {
          final name = '${dark ? 'dark' : 'light'}-${config.$1}-$state.png';
          expect(tester.takeException(), isNull, reason: name);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../artifacts/multi-recipe-sharing/screens/$name',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          manifest.add(name);
        }

        await mount(list());
        await capture('selection-cards-all');
        if (config.$1 == 'desktop') {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          preferences.dispose();
          continue;
        }
        if (config.$1 == 'small-phone' || config.$1 == 'normal-phone') {
          preferences.setFavoritesOnly(true);
          await tester.pumpAndSettle();
          await capture('selection-cards-favorites');
          preferences.setView(RecipeView.compact);
          await tester.pumpAndSettle();
          await capture('selection-compact-favorites');
          preferences.setFavoritesOnly(false);
          await tester.pumpAndSettle();
          await capture('selection-compact-all');
          preferences.setView(RecipeView.cards);
        }
        selection = null;
        await mount(list());
        await tester.ensureVisible(find.text(existing.fields.title).first);
        await tester.longPress(find.text(existing.fields.title).first);
        await tester.pumpAndSettle();
        await capture('actions');
        await mount(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showShareOptions(context, isAndroid: true),
                  child: const Text('Share recipes'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Share recipes'));
        await tester.pumpAndSettle();
        await capture('share-options');
        TextImportBlock block(Recipe value) => TextImportBlock(
          text: value.fields.title,
          candidate: Candidate(
            recipe: value,
            warnings: const [],
            ingredientSources: const [],
          ),
        );
        await mount(
          TextImportReview(
            blocks: [
              block(recipe('exact', title: existing.fields.title)),
              block(
                recipe(
                  'same-name',
                  title: existing.fields.title,
                  notes: 'Different filling and bake time.',
                ),
              ),
              const TextImportBlock(text: 'Malformed synthetic recipe'),
              block(recipe('new', title: 'Roasted carrot and ginger soup')),
            ],
            store: store,
            service: ImportFakeService(),
            onReview: (_, _) async => null,
          ),
        );
        await capture('import-review-top');
        await tester.scrollUntilVisible(
          find.text('Import selected (2)'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await capture('import-review-bottom');
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        preferences.dispose();
      }
    }
    await tester.runAsync(
      () =>
          File('../artifacts/multi-recipe-sharing/screens/manifest.txt')
              .writeAsString('${manifest.join('\n')}\n'),
    );
    expect(manifest, hasLength(54));
  }, skip: Platform.environment['SHARING_SCREENSHOTS'] != '1');
}
