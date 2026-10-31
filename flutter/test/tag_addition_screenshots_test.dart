import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'library_screen_test.dart' show LibraryFakeRepository;
import 'tag_addition_test.dart' show tagFixtures;
import 'import_test.dart' show ShellPlatform, ImportFakeService;

void main() {
  testWidgets('Tag additions short approval checkpoint', (tester) async {
    await loadSectionCaptureFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final files = <String>[];
    RecipeStore? store;
    LocalPreferences? prefs;
    for (final dark in [false, true]) {
      Future<void> mount({
        bool recipes = false,
        Size size = const Size(390, 844),
      }) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        store?.dispose();
        prefs?.dispose();
        tester.view.physicalSize = size;
        prefs = LocalPreferences.memory()
          ..sort = RecipeSort.title
          ..setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        if (recipes) {
          prefs!.query = 'quick';
          prefs!.searchFields = {SearchField.tags};
          prefs!.favoritesOnly = true;
        }
        store = RecipeStore(LibraryFakeRepository(tagFixtures()), prefs!);
        await store!.initialize();
        final app = recipes
            ? CookdexApp(
                store: store!,
                platform: ShellPlatform(),
                importService: ImportFakeService(),
              )
            : MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: cookdexTheme(
                  colors: dark ? cookdexColors : cookdexLightColors,
                ),
                home: const SizedBox.shrink(),
                initialRoute: '/library',
                routes: {
                  '/library': (_) =>
                      LibraryScreen(store: store!, onOpenRecipe: (_, _) {}),
                },
              );
        await tester.pumpWidget(
          RepaintBoundary(key: const Key('capture'), child: app),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String state) async {
        expect(tester.takeException(), isNull, reason: state);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        final name = '${dark ? 'dark' : 'light'}-$state.png';
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/library-tidy/checkpoint-3/screens/$name',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        files.add(name);
      }

      Future<void> tap(String text) async {
        await tester.tap(find.text(text).first);
        await tester.pumpAndSettle();
      }

      Future<void> type(String text) async {
        await tester.enterText(find.byType(TextField).last, text);
        await tester.pumpAndSettle();
      }

      await mount(size: const Size(1600, 900));
      await tap('Tags');
      await tap('quick');
      await capture('full-width-details');
      await mount();
      await tap('Tags');
      await capture('tags-new-button');
      await tap('New tag');
      await type('picnic');
      await capture('new-tag');
      await tap('Choose recipes');
      await capture('recipe-picker');
      await type('quick');
      await tap('Favorites');
      await tap('Select all (10)');
      await capture('picker-selected');
      await tester.tap(find.byTooltip('Search fields'));
      await tester.pumpAndSettle();
      await capture('picker-search-fields');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap('Add');
      await capture('add-confirmation');
      await tap('Cancel');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap('New tag');
      await type('WEEKNIGHT!');
      await capture('new-tag-existing');
      await tap('Cancel');
      await tap('weeknight');
      await tap('Add to recipes…');
      await capture('picker-locked');
      await mount(recipes: true);
      await tester.tap(
        find.text('Garden recipe 000').first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tap('Select');
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      final tooltip = tester.state<RawTooltipState>(find.byTooltip('Add tag'));
      tooltip.ensureTooltipVisible();
      await tester.pumpAndSettle();
      await capture('select-mode');
      await tester.tap(find.byTooltip('Add tag'));
      await tester.pumpAndSettle();
      await type('week');
      await capture('select-tag-suggestions');
      final suggestion = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ListTile, 'weeknight'),
      );
      await tester.tap(suggestion);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        'weeknight',
      );
      await tap('Continue');
      expect(find.text('Add “weeknight” to 9 recipes?'), findsOneWidget);
      await capture('select-tag-confirmation');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    store?.dispose();
    prefs?.dispose();
    await tester.runAsync(
      () async =>
          File('../artifacts/library-tidy/checkpoint-3/screens/manifest.txt')
              .writeAsString('${files.join('\n')}\n'),
    );
    debugDisableShadows = true;
  }, skip: Platform.environment['TAG_ADDITION_SCREENSHOTS'] != '1');
}
