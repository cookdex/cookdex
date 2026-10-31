import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'library_screen_test.dart' show LibraryFakeRepository, libraryFixtures;
import 'library_spelling_test.dart' show spellingFixtures;
import 'tag_addition_test.dart' show tagFixtures;
import 'import_test.dart' show ShellPlatform, ImportFakeService;

const profiles = [
  ('small-phone', Size(320, 800), 1.0),
  ('normal-phone', Size(390, 844), 1.0),
  ('largest-phone', Size(390, 844), 2.0),
  ('tablet-landscape', Size(1280, 800), 1.0),
  ('windows-mouse', Size(1600, 900), 1.0),
];
void main() {
  testWidgets('Library final design matrix', (tester) async {
    await loadSectionCaptureFonts(tester);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final files = <String>[];
    RecipeStore? store;
    LocalPreferences? prefs;
    for (final dark in [false, true]) {
      for (final (profile, size, scale) in profiles) {
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        Future<void> mount({
          bool tags = false,
          bool recipes = false,
          RecipeView view = RecipeView.cards,
          bool favorites = false,
          Widget? home,
        }) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          store?.dispose();
          prefs?.dispose();
          prefs = LocalPreferences.memory()
            ..sort = RecipeSort.title
            ..themeMode = dark ? ThemeMode.dark : ThemeMode.light
            ..recipeTextSize = scale == 2
                ? RecipeTextSize.extraLarge
                : RecipeTextSize.normal
            ..view = view
            ..favoritesOnly = favorites;
          store = RecipeStore(
            LibraryFakeRepository(
              tags || recipes
                  ? tagFixtures()
                  : [...libraryFixtures(), ...spellingFixtures()],
            ),
            prefs!,
          );
          await store!.initialize();
          final app = recipes
              ? CookdexApp(
                  store: store!,
                  platform: ShellPlatform(),
                  importService: ImportFakeService(),
                )
              : MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme:
                      cookdexTheme(
                        colors: dark ? cookdexColors : cookdexLightColors,
                      ).copyWith(
                        platform: profile == 'windows-mouse'
                            ? TargetPlatform.windows
                            : TargetPlatform.android,
                      ),
                  home:
                      home ??
                      LibraryScreen(store: store!, onOpenRecipe: (_, _) {}),
                );
          await tester.pumpWidget(
            RepaintBoundary(key: const Key('capture'), child: app),
          );
          await tester.pumpAndSettle();
        }

        Future<void> shot(String state) async {
          final fileName = '${dark ? 'dark' : 'light'}-$profile-$state.png';
          expect(tester.takeException(), isNull, reason: fileName);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File(
              '../artifacts/library-tidy/final/screens/$fileName',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          files.add(fileName);
        }

        Future<void> tap(String label) async {
          final target = find.text(label);
          if (target.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              target,
              250,
              scrollable: find
                  .byWidgetPredicate(
                    (w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.down,
                  )
                  .last,
            );
          }
          await tester.ensureVisible(target.first);
          await tester.pumpAndSettle();
          await tester.tap(target.first);
          await tester.pumpAndSettle();
        }

        Future<void> type(String text) async {
          await tester.enterText(find.byType(TextField).last, text);
          await tester.pumpAndSettle();
        }

        await mount();
        if (profile == 'windows-mouse') {
          await type('beef');
          await tester.tap(
            find.byKey(const ValueKey(('library-name', true, 'beef'))),
          );
          await tester.pumpAndSettle();
          await shot('selected-ingredient');
          await tap('Tags');
          await type('beef');
          await tester.tap(
            find.byKey(const ValueKey(('library-name', true, 'Beef'))),
          );
          await tester.pumpAndSettle();
          await shot('selected-tag');
          continue;
        }
        await shot('ingredients');
        await tap('Tags');
        await shot('tags');
        await tap('Ingredients');
        await type('parm');
        await tester.tap(
          find.byKey(const ValueKey(('library-name', false, 'parm'))),
        );
        await tester.pumpAndSettle();
        await shot('details');
        await tap('Rename');
        await type('parmesan cheese');
        await shot('rename-warning');
        await tap('Continue');
        await shot('merge-confirmation');
        await tap('Cancel');
        await tap('Merge into…');
        await shot('merge-picker');
        await mount(tags: true);
        await tap('Tags');
        await tap('New tag');
        await type('WEEKNIGHT!');
        await shot('new-tag');
        await tap('Choose recipes');
        await type('quick');
        await tap('Favorites');
        await tap('Select all (9)');
        await shot('tag-picker');
        if (profile == 'small-phone' || profile == 'normal-phone') {
          for (final view in RecipeView.values) {
            for (final favorites in [false, true]) {
              await mount(recipes: true, view: view, favorites: favorites);
              await type('quick');
              // Full selection header plus visible Cards/Compact and filter context.
              await tester.tap(
                find.text('Garden recipe 000').first,
                buttons: kSecondaryMouseButton,
              );
              await tester.pumpAndSettle();
              await tap('Select');
              await tester.tap(find.byTooltip('Select all'));
              await tester.pumpAndSettle();
              await shot(
                'recipes-${view.name}-${favorites ? 'favorites' : 'all'}',
              );
            }
          }
        }
        if (profile == 'normal-phone') {
          await mount(
            home: HowCookdexWorksScreen(
              loadAppInfo: () async => 'cookdex 1.8.5',
              openUrl: (_) async {},
            ),
          );
          await tester.scrollUntilVisible(
            find.byKey(const PageStorageKey('help-library')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tap('Ingredients and tags');
          await shot('help');
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    store?.dispose();
    prefs?.dispose();
    debugDisableShadows = true;
    await tester.runAsync(
      () =>
          File('../artifacts/library-tidy/final/screens/manifest.txt')
              .writeAsString('${files.join('\n')}\n'),
    );
  }, skip: Platform.environment['LIBRARY_DESIGN_SCREENSHOTS'] != '1');
}
