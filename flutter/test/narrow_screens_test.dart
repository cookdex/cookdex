import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, reveal;
import 'import_test.dart' show ImportFakeService, ShellPlatform;
import 'support/polish_fixtures.dart';
import 'sync_controller_test.dart' show FakeSyncBackend, syncStatus;

// Host layout evidence only. These tests neither contact native services nor
// measure device performance. 320dp also models increased Android display size.
const _profiles = [
  ('narrow', Size(320, 780), 1.0, 1.0),
  ('narrow-largest', Size(320, 780), 2.0, 1.3),
  ('small', Size(360, 800), 1.0, 1.0),
  ('normal', Size(412, 892), 1.0, 1.0),
  ('largest', Size(412, 892), 2.0, 1.3),
  ('tablet-landscape', Size(1280, 800), 1.0, 1.0),
];
const _capture = ValueKey('narrow-capture');
final _screenshots = Platform.environment['NARROW_SCREENSHOTS'] == '1';

class _AndroidPlatform extends ShellPlatform {
  @override
  bool get isAndroid => true;
}

Future<void> _fonts(WidgetTester tester) async {
  // Use actual glyph widths even when screenshots are disabled: Ahem masks
  // exactly the compact-control spacing this regression is intended to catch.
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
      final symbols = FontLoader('packages/material_symbols_icons/$family');
      symbols.addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/$family.ttf',
        ),
      );
      await symbols.load();
    }
  });
}

void _viewport(WidgetTester tester, Size size, double scale) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  final phase = Platform.environment['NARROW_PHASE'] ?? 'after';
  expect(phase, isIn(['before', 'after']));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(
      '../artifacts/performance-polish/narrow/$phase-$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final profile in _profiles.where((p) => p.$1 != 'small')) {
    testWidgets('${profile.$1}: settings switch labels retain complete words', (
      tester,
    ) async {
      await _fonts(tester);
      _viewport(tester, profile.$2, profile.$3);
      var awake = false;
      var wallpaper = false;
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
            home: SettingsScreen(
              hasPrevious: false,
              syncSummary: 'Not synced',
              shoppingKeepAwake: false,
              onShoppingKeepAwake: (value) => awake = value,
              recipeTextScale: profile.$4,
              onRecipeTextScale: (_) {},
              isAndroid: true,
              wallpaperColors: false,
              onWallpaperColors: (value) => wallpaper = value,
              version: 'Synthetic layout fixture',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find.descendant(
        of: find.byKey(const PageStorageKey('settings')),
        matching: find.byType(Scrollable),
      );
      for (final entry in [
        ('Keep shopping screen awake', 'shopping'),
        ('Wallpaper colors', 'appearance'),
      ]) {
        await tester.scrollUntilVisible(
          find.text(entry.$1),
          200,
          scrollable: scroll,
        );
        await tester.ensureVisible(find.text(entry.$1));
        await tester.pumpAndSettle();
        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(entry.$1),
        );
        var start = 0;
        for (final word in entry.$1.split(' ')) {
          expect(
            paragraph.getBoxesForSelection(
              TextSelection(
                baseOffset: start,
                extentOffset: start + word.length,
              ),
            ),
            hasLength(1),
            reason: word,
          );
          start += word.length + 1;
        }
        final tile = find.ancestor(
          of: find.text(entry.$1),
          matching: find.byType(SwitchListTile),
        );
        expect(tester.getRect(tile).right, lessThanOrEqualTo(profile.$2.width));
        expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
        await _shot(tester, '${profile.$1}-settings-${entry.$2}-toggle');
        await tester.tap(find.text(entry.$1));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(awake, isTrue);
      expect(wallpaper, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final profile in _profiles.where((p) => p.$1 != 'small')) {
    testWidgets(
      '${profile.$1}: detail toolbar controls fit in both cook states',
      (tester) async {
        await _fonts(tester);
        _viewport(tester, profile.$2, profile.$3);
        final prefs = LocalPreferences.memory();
        final store = RecipeStore(PolishRepository(), prefs);
        await store.initialize();
        final cook = CookController(preferences: prefs, setWake: (_) async {});
        var edits = 0;
        var menus = 0;
        await tester.pumpWidget(
          RepaintBoundary(
            key: _capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
              builder: (_, child) =>
                  RecipeTextScale(factor: profile.$4, child: child!),
              home: Scaffold(
                body: RecipeDetail(
                  store: store,
                  recipeId: '0',
                  cook: cook,
                  onBack: () {},
                  onActions: () => menus++,
                  onEdit: () => edits++,
                  onSource: (_) async {},
                  onAddToShopping: () {},
                ),
              ),
            ),
          ),
        );
        for (final active in [false, true]) {
          if (active) await tester.tap(find.byKey(const Key('cook-toggle')));
          await tester.pumpAndSettle();
          expect(cook.active, active);
          expect(tester.takeException(), isNull);
          await _shot(
            tester,
            '${profile.$1}-detail-toolbar-${active ? 'cooking' : 'idle'}',
          );
          for (final target in [
            find.byTooltip('Back to recipes'),
            find.byKey(const Key('cook-toggle')),
            find.byTooltip('Edit recipe'),
            find.byTooltip('Unfavorite recipe'),
            find.byTooltip('Recipe actions'),
          ]) {
            final rect = tester.getRect(target);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(profile.$2.width));
            expect(rect.width, greaterThanOrEqualTo(48));
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(target.hitTestable(), findsOneWidget);
          }
          await tester.tap(find.byTooltip('Edit recipe'));
          await tester.tap(find.byTooltip('Recipe actions'));
        }
        expect(edits, 2);
        expect(menus, 2);
        if (profile.$1 == 'narrow-largest') {
          // Exercise the second-row fallback below the supported 320dp floor;
          // at 320dp these real-font controls still fit in a single row.
          tester.view.physicalSize = const Size(280, 780);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester.getSize(find.byKey(const Key('recipe-toolbar'))).height,
            greaterThan(48),
          );
          for (final tooltip in [
            'Edit recipe',
            'Unfavorite recipe',
            'Recipe actions',
          ]) {
            final target = find.byTooltip(tooltip);
            expect(tester.getRect(target).right, lessThanOrEqualTo(280));
            expect(target.hitTestable(), findsOneWidget);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        cook.dispose();
        store.dispose();
        prefs.dispose();
      },
    );
  }

  for (final profile in _profiles.where((p) => p.$1 != 'small')) {
    testWidgets(
      '${profile.$1}: recipe controls retain one row and remain reachable',
      (tester) async {
        await _fonts(tester);
        _viewport(tester, profile.$2, profile.$3);
        final prefs = LocalPreferences.memory();
        if (profile.$4 > 1) prefs.setRecipeTextSize(RecipeTextSize.extraLarge);
        final store = RecipeStore(PolishRepository(), prefs);
        await store.initialize();
        await tester.pumpWidget(
          RepaintBoundary(
            key: _capture,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
              home: Scaffold(
                body: RecipesScreen(
                  store: store,
                  preferences: prefs,
                  onOpenRecipe: (_) {},
                  onAdd: () {},
                  onActions: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _shot(tester, '${profile.$1}-recipes-toolbar');
        for (final sort in RecipeSort.values) {
          prefs.setSort(sort);
          for (final favorites in [false, true]) {
            prefs.setFavoritesOnly(favorites);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            for (final target in [
              find.widgetWithText(FilterChip, 'Favorites'),
              find.byWidgetPredicate(
                (w) => w is ActionChip && w.tooltip == 'Sort recipes',
              ),
              find.byWidgetPredicate(
                (w) => w is IconButton && w.key == const Key('recipe-view'),
              ),
            ]) {
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              final rect = tester.getRect(target);
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(profile.$2.width));
              expect(rect.height, greaterThanOrEqualTo(48));
              expect(target.hitTestable(), findsOneWidget);
            }
          }
        }
        // The last trigger remains usable after scrolling it into view.
        await tester.tap(find.byKey(const Key('recipe-view')));
        await tester.pumpAndSettle();
        expect(prefs.view, RecipeView.compact);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        prefs.dispose();
      },
    );
  }

  for (final profile in _profiles) {
    testWidgets('${profile.$1}: ingredient delete stays visible idle and active', (
      tester,
    ) async {
      await _fonts(tester);
      _viewport(tester, profile.$2, profile.$3);
      final (c, _, _) = await controller();
      c.draft.title = 'Roasted vegetables and lentils';
      final row = EditableIngredient(
        amount: '1/2–1 1/2',
        unit: 'cup',
        name: 'Green lentils',
      );
      c.draft.sections.first.rows
        ..clear()
        ..add(row);
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
            builder: (_, child) =>
                RecipeTextScale(factor: profile.$4, child: child!),
            home: RecipeEditor(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Reveal the amount rather than Delete: ensureVisible(Delete) would
      // horizontally scroll the controls and hide the owner's reported defect.
      final amount = find.byKey(ValueKey('${row.id}-amount'));
      await reveal(tester, amount);
      final problems = <String>[];
      Future<void> check(String state) async {
        await tester.pumpAndSettle();
        await _shot(tester, '${profile.$1}-editor-$state');
        expect(tester.takeException(), isNull);
        for (final part in ['amount', 'unit', 'name']) {
          final field = find.byKey(ValueKey('${row.id}-$part'));
          final bounds = tester.getRect(field);
          if (bounds.left < 0 || bounds.right > profile.$2.width) {
            problems.add('$state $part $bounds exceeds ${profile.$2.width}dp');
          }
        }
        final target = find.byTooltip('Delete ingredient 1');
        final rect = tester.getRect(target);
        if (rect.left < 0 ||
            rect.right > profile.$2.width ||
            rect.width < 48 ||
            rect.height < 48) {
          problems.add(
            '$state Delete $rect must fit ${profile.$2.width}dp with a 48dp target',
          );
        }
        // Geometry alone does not catch a button clipped by a narrower ancestor.
        if (target.hitTestable().evaluate().isEmpty) {
          problems.add('$state Delete is clipped or not hit-testable');
        }
      }

      await check('idle');
      await tester.tap(amount);
      await tester.pumpAndSettle();
      await check('active');
      await tester.pumpWidget(const SizedBox.shrink());
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  for (final profile in _profiles.take(2)) {
    testWidgets('${profile.$1}: shell screens and import fit', (tester) async {
      await _fonts(tester);
      _viewport(tester, profile.$2, profile.$3);
      final prefs = LocalPreferences.memory();
      if (profile.$4 > 1) prefs.setRecipeTextSize(RecipeTextSize.extraLarge);
      final store = RecipeStore(PolishRepository(), prefs);
      final problems = <String>[];
      await store.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: CookdexApp(
            store: store,
            platform: _AndroidPlatform(),
            importService: ImportFakeService(),
          ),
        ),
      );
      Future<void> shot(String name) async {
        await tester.pumpAndSettle();
        await _shot(tester, '${profile.$1}-$name');
        expect(tester.takeException(), isNull, reason: name);
      }

      Future<void> tap(Finder target) async {
        if (target.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            target,
            250,
            scrollable: find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .last,
          );
        }
        await tester.ensureVisible(target.first);
        await tester.pumpAndSettle();
        await tester.tap(target.first);
        await tester.pumpAndSettle();
      }

      await shot('recipes');
      prefs.setView(RecipeView.compact);
      await shot('recipes-compact');
      await tap(find.text('Family pork supper'));
      await shot('detail');
      await tap(find.text('Cook'));
      await shot('cook');
      final actions = find.byTooltip('Recipe actions');
      if (tester.getRect(actions).right > profile.$2.width ||
          actions.hitTestable().evaluate().isEmpty) {
        problems.add(
          'Recipe actions must be visible without horizontal toolbar scrolling',
        );
      }
      await tap(find.text('Shopping list').last);
      await shot('shopping');
      await tap(find.byTooltip('Shopping list options'));
      await tap(find.text('Categories'));
      await shot('categories');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(find.text('Settings').last);
      await shot('settings');
      await tap(find.text('Recipe text size'));
      await shot('appearance');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await shot('settings-appearance');
      await tap(find.text('How cookdex works'));
      await shot('help');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tap(find.text('Recipes').last);
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
      await shot('smart-settings');
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  for (final profile in _profiles.where((p) => p.$1 != 'small')) {
    testWidgets('${profile.$1}: sync status fits', (tester) async {
      await _fonts(tester);
      _viewport(tester, profile.$2, profile.$3);
      final prefs = LocalPreferences.memory();
      final store = RecipeStore(PolishRepository(), prefs);
      await store.initialize();
      final backend = FakeSyncBackend();
      backend.current = syncStatus(
        peers: const [
          SyncPeer(
            id: 'synthetic-tablet',
            name: 'Kitchen tablet with a long device name',
            address: '192.0.2.10:47832',
            caughtUp: true,
          ),
        ],
      );
      final sync = SyncController(
        backend: backend,
        refreshRecipes: store.refresh,
        isAndroid: true,
        requestPermission: () async => true,
      );
      await sync.refresh();
      await tester.pumpWidget(
        RepaintBoundary(
          key: _capture,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
            home: SyncScreen(controller: sync, store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _shot(tester, '${profile.$1}-sync');
      expect(tester.takeException(), isNull);
      final label = find.text('Not synced');
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(
        paragraph.getBoxesForSelection(
          const TextSelection(baseOffset: 0, extentOffset: 10),
        ),
        hasLength(1),
      );
      final button = find.byKey(const ValueKey('sync-now'));
      final bounds = tester.getRect(button);
      expect(bounds.right, lessThanOrEqualTo(profile.$2.width - 16));
      expect(bounds.height, greaterThanOrEqualTo(48));
      expect(button.hitTestable(), findsOneWidget);
      if (profile.$1 == 'narrow-largest') {
        expect(bounds.top, greaterThan(tester.getRect(label).bottom));
      }
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
      store.dispose();
      prefs.dispose();
    });
  }
}
