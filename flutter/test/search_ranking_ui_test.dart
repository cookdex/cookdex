import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'recipe_store_test.dart' show FakeRepository;
import 'search_ranking_test.dart' show searchScreenshotsRecipes, searchRecipe;

void main() {
  for (final width in [390.0, 1280.0]) {
    for (final view in RecipeView.values) {
      testWidgets(
        '$width $view group boundary stays fixed through shell fill',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          CardShellMetrics.enabled = true;
          CardShellMetrics.reset();
          addTearDown(() => CardShellMetrics.enabled = false);
          final prefs = LocalPreferences.memory()..view = view;
          final store = RecipeStore(
            FakeRepository([
              ...searchScreenshotsRecipes(),
              for (var i = 0; i < 100; i++)
                searchRecipe('extra-$i', 'Rice supper $i'),
            ]),
            prefs,
          );
          await store.initialize();
          prefs.setQuery('chicken rice');
          await tester.pumpWidget(
            CookdexApp(
              store: store,
              platform: ShellPlatform(),
              importService: ImportFakeService(),
            ),
          );
          final label = find.byKey(const Key('partial-matches'));
          expect(label, findsOneWidget);
          final before = tester.getRect(label);
          final full = tester.getRect(find.byKey(const ValueKey('a')));
          final partial = tester.getRect(find.byKey(const ValueKey('b')));
          expect(before.top, greaterThanOrEqualTo(full.bottom));
          expect(partial.top, greaterThanOrEqualTo(before.bottom));
          for (var i = 0; i < 25; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(tester.getRect(label), before);
          }
          expect(CardShellMetrics.snapshot()['sizeChanges'], 0);
          final results = store.visibleRecipes;
          final list = find.byKey(const PageStorageKey('recipes-scroll'));
          await tester.drag(list, const Offset(0, -1000));
          await tester.pumpAndSettle();
          expect(identical(results, store.visibleRecipes), true);
          final state = tester.state<RecipesScreenState>(
            find.byType(RecipesScreen),
          );
          state.scrollToTop();
          await tester.pumpAndSettle();
          expect(tester.getRect(label), before);
          prefs.setQuery('chicken');
          await tester.pumpAndSettle();
          expect(label, findsNothing);
          prefs.setQuery('lemon herbs');
          await tester.pumpAndSettle();
          expect(label, findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          prefs.dispose();
        },
        semanticsEnabled: false,
      );
    }
  }
  testWidgets('search ranking real-font host states', (tester) async {
    await loadSectionCaptureFonts(tester);
    await tester.runAsync(() async {
      final font = FontLoader('Segoe UI');
      for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
        font.addFont(
          File('${Platform.environment['WINDIR']}/Fonts/$name')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await font.load();
    });
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const output = '../artifacts/search-ranking/screenshots';
    final manifest = <Map<String, Object>>[];
    for (final dark in [false, true]) {
      for (final (profile, size, scale) in [
        ('small-phone', const Size(320, 800), 1.0),
        ('normal-phone', const Size(390, 844), 1.0),
        ('largest-phone', const Size(390, 844), 2.0),
        ('tablet-landscape', const Size(1280, 800), 1.0),
        ('windows', const Size(1280, 800), 1.0),
      ]) {
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        debugDefaultTargetPlatformOverride = profile == 'windows'
            ? TargetPlatform.windows
            : TargetPlatform.android;
        for (final view in RecipeView.values) {
          for (final favorites in [
            false,
            if (profile == 'small-phone' || profile == 'normal-phone') true,
          ]) {
            final prefs = LocalPreferences.memory()
              ..themeMode = dark ? ThemeMode.dark : ThemeMode.light
              ..recipeTextSize = scale > 1
                  ? RecipeTextSize.extraLarge
                  : RecipeTextSize.normal
              ..view = view
              ..favoritesOnly = favorites;
            final store = RecipeStore(
              FakeRepository(searchScreenshotsRecipes()),
              prefs,
            );
            await store.initialize();
            prefs.setQuery('chicken rice');
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('search-capture'),
                child: CookdexApp(
                  store: store,
                  platform: ShellPlatform(),
                  importService: ImportFakeService(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            Future<void> shot(String state) async {
              final name =
                  '${dark ? 'dark' : 'light'}-$profile-${view.name}-${favorites ? 'favorites' : 'all'}-$state.png';
              expect(tester.takeException(), isNull, reason: name);
              final label = find.byKey(const Key('partial-matches'));
              expect(label, state == 'mixed' ? findsOneWidget : findsNothing);
              if (state == 'mixed') {
                final rect = tester.getRect(label);
                expect(rect.bottom, lessThan(size.height - 80), reason: name);
                expect(rect.left, greaterThanOrEqualTo(16));
              }
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('search-capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final data = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final file = File('$output/$name');
                await file.parent.create(recursive: true);
                await file.writeAsBytes(data!.buffer.asUint8List());
                image.dispose();
              });
              manifest.add({
                'file': name,
                'width': size.width,
                'height': size.height,
                'scale': scale,
                'query': prefs.query,
                'state': state,
              });
            }

            await shot('mixed');
            if (profile == 'normal-phone' &&
                view == RecipeView.cards &&
                !favorites) {
              prefs.setQuery('chicken');
              await tester.pumpAndSettle();
              await shot('single');
              prefs.setQuery('lemon herbs');
              await tester.pumpAndSettle();
              await shot('full-only');
            }
            await tester.pumpWidget(const SizedBox.shrink());
            store.dispose();
            prefs.dispose();
          }
        }
      }
    }
    await tester.runAsync(
      () => File('$output/manifest.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest)),
    );
    debugDefaultTargetPlatformOverride = null;
    debugDisableShadows = true;
  }, skip: Platform.environment['SEARCH_RANKING_SCREENSHOTS'] != '1');
}
