import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'library_screen_test.dart' show LibraryFakeRepository, libraryFixtures;

void main() {
  testWidgets('Library phone and tablet approval states', (tester) async {
    await loadSectionCaptureFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final files = <String>[];
    for (final dark in [false, true]) {
      tester.view.physicalSize = const Size(390, 844);
      final prefs = LocalPreferences.memory();
      final store = RecipeStore(
        LibraryFakeRepository(libraryFixtures()),
        prefs,
      );
      await store.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme(
              colors: dark ? cookdexColors : cookdexLightColors,
            ).copyWith(platform: TargetPlatform.android),
            home: const SizedBox.shrink(),
            initialRoute: '/library',
            routes: {
              '/library': (_) =>
                  LibraryScreen(store: store, onOpenRecipe: (_, _) {}),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
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
            '../artifacts/library-tidy/checkpoint/screens/$name',
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

      Future<void> back() async {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await capture('ingredients');
      await tap('Tags');
      await capture('tags');
      await tap('weeknight');
      await capture('tag-details');
      await tap('Remove tag');
      await capture('remove-tag');
      await tap('Cancel');
      await back();
      await tap('Ingredients');
      await tester.enterText(find.byType(TextField), 'par');
      await tester.pumpAndSettle();
      await capture('search');
      await tester.enterText(find.byType(TextField), 'nutmeg');
      await tester.pumpAndSettle();
      await capture('no-matches');
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tap('parm');
      await capture('details');
      await tap('Show all (6)');
      await capture('show-all');
      await back();
      await tap('Rename');
      await capture('rename');
      await tester.enterText(find.byType(TextField).last, 'parmesan cheese');
      await tester.pumpAndSettle();
      await capture('rename-merge-warning');
      await tap('Cancel');
      await tap('Merge into…');
      await capture('merge-picker');
      await tester.enterText(find.byType(TextField).last, 'parmesan');
      await tester.pumpAndSettle();
      await capture('merge-search');
      await tap('parmesan cheese');
      await capture('merge-confirmation');
      await tap('Merge');
      await capture('undo');
      await tap('Undo');
      await back();
      await tap('Merge');
      await capture('duplicates-confirmation');
      await tap('Cancel');
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      await tap('parm');
      await capture('tablet-ingredients');
      await tap('Tags');
      await tap('weeknight');
      await capture('tablet-tags');
      final mouse = await tester.startGesture(
        tester.getCenter(find.text('weeknight').first),
        kind: ui.PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.up();
      await tester.pumpAndSettle();
      await capture('row-actions');
      await tester.tapAt(const Offset(1200, 750));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      store.dispose();
      prefs.dispose();

      tester.view.physicalSize = const Size(390, 844);
      final emptyPrefs = LocalPreferences.memory();
      final empty = RecipeStore(LibraryFakeRepository([]), emptyPrefs);
      await empty.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme(
              colors: dark ? cookdexColors : cookdexLightColors,
            ),
            home: const SizedBox.shrink(),
            initialRoute: '/library',
            routes: {
              '/library': (_) =>
                  LibraryScreen(store: empty, onOpenRecipe: (_, _) {}),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('empty-ingredients');
      await tap('Tags');
      await capture('empty-tags');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      empty.dispose();
      emptyPrefs.dispose();
    }
    await tester.runAsync(
      () async =>
          File('../artifacts/library-tidy/checkpoint/screens/manifest.txt')
              .writeAsString('${files.join('\n')}\n'),
    );
    debugDisableShadows = true;
  }, skip: Platform.environment['LIBRARY_SCREENSHOTS'] != '1');
}
