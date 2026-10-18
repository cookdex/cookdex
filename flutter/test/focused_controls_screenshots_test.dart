import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/polish_fixtures.dart';
import 'shopping_screen_test.dart' as shopping;

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

void main() {
  for (final config in [
    ('small', const Size(320, 800), 1.0),
    ('normal', const Size(390, 844), 1.0),
    ('largest', const Size(390, 844), 2.0),
    ('tablet-landscape', const Size(1280, 800), 1.0),
  ]) {
    testWidgets('${config.$1}: stable recipe controls and rendered menu', (
      tester,
    ) async {
      await _fonts(tester);
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = LocalPreferences.memory();
      if (config.$1 == 'largest') {
        prefs.setRecipeTextSize(RecipeTextSize.extraLarge);
      }
      final store = RecipeStore(PolishRepository(), prefs);
      await store.initialize();
      Widget app(Widget child) => RepaintBoundary(
        key: const Key('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(config.$3)),
            child: child!,
          ),
          home: child,
        ),
      );
      Future<void> shot(String name) async {
        expect(tester.takeException(), isNull);
        if (Platform.environment['FOCUSED_POLISH_SCREENSHOTS'] != '1') return;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/focused-polish/screens/${config.$1}-$name.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        app(
          Scaffold(
            body: RecipesScreen(
              store: store,
              preferences: prefs,
              onOpenRecipe: (_) {},
              onAdd: () {},
              onActions: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final favorites = find.widgetWithText(FilterChip, 'Favorites');
      final sort = find.byWidgetPredicate(
        (w) => w is ActionChip && w.tooltip == 'Sort recipes',
      );
      final view = find.byKey(const Key('recipe-view'));
      final initial = [
        tester.getRect(favorites),
        tester.getRect(sort),
        tester.getRect(view),
      ];
      expect(initial[0].center.dy, initial[1].center.dy);
      expect(initial[0].center.dy, initial[2].center.dy);
      if (config.$1 == 'normal') {
        expect(initial[2].right, lessThanOrEqualTo(config.$2.width - 16));
      }
      expect(tester.widget<FilterChip>(favorites).showCheckmark, isFalse);
      for (final selectedView in RecipeView.values) {
        prefs.setView(selectedView);
        for (final selectedFavorites in [false, true]) {
          prefs.setFavoritesOnly(selectedFavorites);
          await tester.pumpAndSettle();
          expect([
            tester.getRect(favorites),
            tester.getRect(sort),
            tester.getRect(view),
          ], initial);
          await shot(
            'recipes-${selectedView.name}-favorites-${selectedFavorites ? 'on' : 'off'}',
          );
        }
      }
      for (final selectedSort in RecipeSort.values) {
        prefs.setSort(selectedSort);
        await tester.pumpAndSettle();
        expect([
          tester.getRect(favorites),
          tester.getRect(sort),
          tester.getRect(view),
        ], initial);
      }
      await tester.ensureVisible(view);
      await tester.pumpAndSettle();
      expect(view.hitTestable(), findsOneWidget);
      await tester.tap(view);
      await tester.pumpAndSettle();
      await shot('recipes-view-toggled');
      expect(prefs.view, RecipeView.cards);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
      final (shoppingStore, _) = await shopping.setup([
        shopping.item('flour', 'Flour', quantity: '2 cups', category: 'pantry'),
        shopping.item('carrots', 'Carrots', quantity: '3', category: 'produce'),
      ]);
      await tester.pumpWidget(
        app(ShoppingScreen(store: shoppingStore, onSaveText: (_) async {})),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('2 cups Flour'));
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsOneWidget);
      await shot('shopping-long-press');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
