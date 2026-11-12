import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/library_catalog.dart';
import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/pixel_scroll.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'library_screen_test.dart' show LibraryFakeRepository;
import 'library_spelling_test.dart' show spellingFixtures;
import 'tag_addition_test.dart' show tagFixtures;
import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'editor_test.dart' show controller, reveal;
import 'shopping_screen_test.dart' as shopping;
import 'sync_controller_test.dart' show FakeSyncBackend;

void main() {
  testWidgets('Smarter duplicates fourth UI checkpoint', (tester) async {
    await loadSectionCaptureFonts(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final files = <String>[];
    RecipeStore? store;
    LocalPreferences? prefs;
    var scale = 1.0;
    for (final dark in [false, true]) {
      Widget wrap(Widget home) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: cookdexTheme(colors: dark ? cookdexColors : cookdexLightColors)
            .copyWith(platform: TargetPlatform.android),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      );
      Future<void> mount({
        bool recipes = false,
        bool tags = false,
        double textScale = 1,
      }) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        store?.dispose();
        prefs?.dispose();
        tester.view.viewInsets = const FakeViewPadding();
        scale = textScale;
        prefs = LocalPreferences.memory()
          ..sort = RecipeSort.title
          ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
        if (recipes) {
          prefs!.query = 'quick';
          prefs!.favoritesOnly = true;
        }
        store = RecipeStore(
          LibraryFakeRepository(
            tags || recipes ? tagFixtures() : spellingFixtures(),
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
            : wrap(LibraryScreen(store: store!, onOpenRecipe: (_, _) {}));
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
            '../artifacts/library-tidy/checkpoint-4/screens/$name',
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

      Future<void> keyboard(String label) async {
        await tester.tap(find.byType(TextField).last);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        final top = tester.getTopLeft(find.text(label).last).dy;
        expect(top, greaterThan(0));
        expect(top, lessThan(544));
        final scroll = find.byType(PixelSingleChildScrollView);
        if (scroll.evaluate().isNotEmpty) {
          expect(
            top,
            greaterThanOrEqualTo(tester.getTopLeft(scroll.last).dy),
            reason: '$label above scroll clip',
          );
        }
      }

      await mount();
      await capture('ingredients-duplicates');
      await tap('Tags');
      await capture('tags-duplicates');
      await tap('Show all (7)');
      await capture('possible-duplicates');
      await tap('Keep separate');
      await capture('keep-separate-undo');
      await tap('Undo');
      await tap('Keep separate');
      // Clear the message and reveal the persistent section at the bottom.
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Kept separate (1)'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text('Show again'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('kept-separate');
      // Dismiss the other exact groups to prove the recovery page stays reachable.
      for (final g in LibraryCatalog(
        store!.summaries,
        LibraryKind.tags,
      ).duplicates) {
        prefs!.keepSeparate('tags', g.map((n) => n.name));
      }
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await capture('all-kept-library');
      await tap('Kept separate (7)');
      await capture('all-kept-page');
      await mount();
      await type('cumin');
      await capture('library-search');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('library-name', false, 'cumin'))),
      );
      await tester.pumpAndSettle();
      await tap('Merge into…');
      await type('cum');
      await capture('merge-search');
      await mount(tags: true);
      await tap('Tags');
      await tap('New tag');
      expect(tester.testTextInput.isVisible, isFalse);
      await capture('new-tag-idle');
      await type('WEEKNIGHT!');
      await keyboard('Tag name');
      await capture('new-tag-keyboard');
      tester.view.viewInsets = const FakeViewPadding();
      await tap('Choose recipes');
      await type('quick');
      await tap('Favorites');
      expect(find.text('Select all (9)'), findsOneWidget);
      expect(
        find.text('1 already tagged · checked and locked'),
        findsOneWidget,
      );
      await capture('picker-search-counts');
      await mount(tags: true, textScale: 2);
      await tap('Tags');
      await tap('New tag');
      await type('week');
      await keyboard('Tag name');
      await capture('new-tag-keyboard-large');
      await mount(recipes: true);
      await capture('recipes-search');
      await tester.tap(
        find.text('Garden recipe 000').first,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tap('Select');
      await tester.tap(find.byTooltip('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add tag'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      await capture('add-tag-idle');
      await type('week');
      await keyboard('Tag name');
      await capture('add-tag-keyboard');
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pumpAndSettle();
      await keyboard('Tag name');
      await capture('add-tag-keyboard-large');
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await mount();
      await type('cumin');
      await tester.tap(
        find.byKey(const ValueKey(('library-name', false, 'cumin'))),
      );
      await tester.pumpAndSettle();
      await tap('Rename');
      await keyboard('Name');
      await capture('rename-keyboard');
      await mount(textScale: 2);
      await type('cumin');
      await tester.tap(
        find.byKey(const ValueKey(('library-name', false, 'cumin'))),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Rename'));
      await tap('Rename');
      await keyboard('Name');
      await capture('rename-keyboard-large');
      for (final large in [false, true]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding();
        scale = large ? 2 : 1;
        final (editor, _, _) = await controller();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: wrap(RecipeEditor(controller: editor)),
          ),
        );
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Section'));
        await tap('Section');
        await type('Topping');
        await keyboard('Name');
        await capture('section-keyboard${large ? '-large' : ''}');
        await tap('Cancel');
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        for (final kind in ['ingredients', 'steps']) {
          await reveal(tester, find.text('Paste $kind'));
          await tap('Paste $kind');
          await type(kind == 'steps' ? 'Mix gently.' : '1 cup flour');
          await keyboard(kind == 'steps' ? 'Steps' : 'Ingredients');
          if (large) await capture('paste-$kind-keyboard-large');
          await tap('Close');
          editor.clearPaste();
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }

      // Audit the remaining real text-entry dialogs at both sizes. Only the
      // largest captures are added to this checkpoint's supporting gallery.
      for (final large in [false, true]) {
        scale = large ? 2 : 1;
        Future<void> auditHome(Widget home) async {
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            RepaintBoundary(key: const Key('capture'), child: wrap(home)),
          );
          await tester.pumpAndSettle();
        }

        final (shoppingStore, _) = await shopping.setup([
          shopping.item('carrots', 'Carrots', category: 'produce'),
        ]);
        await auditHome(
          ShoppingScreen(store: shoppingStore, onSaveText: (_) async {}),
        );
        await shopping.menu(tester, 'Categories');
        await tap('Add category');
        await type('Frozen');
        await keyboard('Name');
        if (large) await capture('category-add-keyboard-large');
        await tap('Cancel');
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        await tap('Produce');
        await keyboard('Name');
        if (large) await capture('category-rename-keyboard-large');
        await tap('Cancel');
        await tester.pageBack();
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding();
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Carrots'));
        await tester.pumpAndSettle();
        await tap('Edit');
        await keyboard('Item');
        if (large) await capture('shopping-edit-keyboard-large');
        await tap('Cancel');
        final sync = SyncController(
          backend: FakeSyncBackend(),
          refreshRecipes: store!.refresh,
          isAndroid: false,
          requestPermission: () async => true,
        );
        await sync.refresh();
        await auditHome(SyncScreen(controller: sync, store: store!));
        await reveal(tester, find.text('Device name'));
        await tap('Device name');
        await tester.tap(find.byType(TextField).last);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(
          tester.getBottomRight(find.byType(TextField).last).dy,
          lessThan(544),
        );
        if (large) await capture('device-name-keyboard-large');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        sync.dispose();
        final importer = ImportController(
          service: ImportFakeService(),
          storage: MemoryDraftStorage(),
        );
        await auditHome(
          ImportScreen(controller: importer, onReview: (_, _) async => null),
        );
        await reveal(tester, find.text('Smart Import settings'));
        await tap('Smart Import settings');
        final keyField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'Gemini key',
        );
        await tester.tap(keyField);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Gemini key')).dy,
          greaterThanOrEqualTo(
            tester.getTopLeft(find.byType(PixelSingleChildScrollView).last).dy,
          ),
        );
        if (large) await capture('import-key-keyboard-large');
        FocusManager.instance.primaryFocus?.unfocus();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Advanced'));
        await tap('Advanced');
        await tester.ensureVisible(find.byType(TextField).last);
        await keyboard('Custom model ID');
        if (large) await capture('import-model-keyboard-large');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        importer.dispose();
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    store?.dispose();
    prefs?.dispose();
    await tester.pump(const Duration(seconds: 2));
    debugDisableShadows = true;
    await tester.runAsync(
      () =>
          File('../artifacts/library-tidy/checkpoint-4/screens/manifest.txt')
              .writeAsString('${files.join('\n')}\n'),
    );
  }, skip: Platform.environment['LIBRARY_SPELLING_SCREENSHOTS'] != '1');
}
