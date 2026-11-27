import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/app_navigation.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'fixtures/wide_navigation_test_support.dart';
import 'import_test.dart' show ImportFakeService, ShellPlatform;
import 'recipe_store_test.dart' show FakeRepository, recipe;

class _Platform extends ShellPlatform {
  _Platform(this.isAndroid);
  @override
  final bool isAndroid;
}

void main() {
  for (final dark in [false, true]) {
    for (final desktop in [false, true]) {
      testWidgets('rail keeps 80 dp, complete labels and contained paint '
          '${dark ? "dark" : "light"} ${desktop ? "Windows" : "Android"}', (
        tester,
      ) async {
        await loadWideNavigationFonts(tester, desktop: desktop);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final prefs = LocalPreferences.memory();
        final store = RecipeStore(FakeRepository([]), prefs);
        await store.initialize();
        addTearDown(() {
          store.dispose();
          prefs.dispose();
        });
        final theme =
            cookdexTheme(colors: dark ? cookdexColors : cookdexLightColors)
                .copyWith(
                  platform: desktop
                      ? TargetPlatform.windows
                      : TargetPlatform.android,
                );
        const frame = Key('rail-paint-frame');

        for (final scale in [1.0, 1.5]) {
          for (final size in [
            const Size(844, 390),
            const Size(1280, 800),
            const Size(1440, 900),
          ]) {
            tester.view.physicalSize = size;
            for (var selected = 0; selected < 3; selected++) {
              await tester.pumpWidget(
                RepaintBoundary(
                  key: frame,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    theme: theme,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: Scaffold(
                      body: Row(
                        children: [
                          AppNavigation(
                            store: store,
                            selected: selected,
                            onSelect: (_) {},
                            rail: true,
                          ),
                          Expanded(
                            child: ColoredBox(
                              color: theme.colorScheme.surface,
                              child: const SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              final rail = find.byType(NavigationRail);
              final bounds = tester.getRect(rail);
              expect(bounds, Rect.fromLTWH(0, 0, 80, size.height));
              expect(
                find.descendant(of: rail, matching: find.byType(FittedBox)),
                findsNothing,
              );

              final iconCenters = [
                for (final symbol in [
                  Symbols.menu_book,
                  Symbols.shopping_cart,
                  Symbols.settings,
                ])
                  tester.getCenter(
                    find
                        .descendant(of: rail, matching: find.byIcon(symbol))
                        .first,
                  ),
              ];
              for (final center in iconCenters) {
                expect(center.dx, 40);
              }
              expect(
                iconCenters[1].dy - iconCenters[0].dy,
                closeTo(iconCenters[2].dy - iconCenters[1].dy, .01),
              );
              final labelHeights = <double>{};
              for (final label in ['Recipes', 'Shopping\nlist', 'Settings']) {
                final labelText = find.descendant(
                  of: rail,
                  matching: find.text(label),
                );
                final labelSlot = tester.getRect(
                  find
                      .ancestor(
                        of: labelText,
                        matching: find.byWidgetPredicate(
                          (widget) =>
                              widget is SizedBox &&
                              widget.width == 80 &&
                              widget.height != null,
                        ),
                      )
                      .first,
                );
                final paragraph = tester.renderObject<RenderParagraph>(
                  find.descendant(
                    of: labelText,
                    matching: find.byType(RichText),
                  ),
                );
                labelHeights.add(labelSlot.height);
                final destinationBounds = tester.getRect(
                  find
                      .ancestor(
                        of: labelText,
                        matching: find.byWidgetPredicate(
                          (widget) => widget is InkResponse,
                        ),
                      )
                      .first,
                );
                expect(paragraph.textScaler.scale(12), 12 * scale);
                final origin = paragraph.localToGlobal(Offset.zero);
                final lines = paragraph
                    .getBoxesForSelection(
                      TextSelection(baseOffset: 0, extentOffset: label.length),
                    )
                    .where((box) => box.right > box.left)
                    .toList();
                expect(lines, hasLength(label.contains('\n') ? 2 : 1));
                expect(
                  lines.map((line) => line.top).toSet(),
                  hasLength(label.contains('\n') ? 2 : 1),
                  reason: '$label must retain its actual line count at $scale',
                );
                for (final line in lines) {
                  final painted = line.toRect().shift(origin);
                  expect(painted.left, greaterThanOrEqualTo(bounds.left));
                  expect(painted.right, lessThanOrEqualTo(bounds.right));
                  expect(painted.top, greaterThanOrEqualTo(bounds.top));
                  expect(painted.bottom, lessThanOrEqualTo(bounds.bottom));
                  // Selection boxes include font metrics beyond tight leading.
                  // The label slot does not clip them; the complete destination
                  // is the boundary for visible, non-overlapping label paint.
                  expect(
                    painted.top,
                    greaterThanOrEqualTo(destinationBounds.top),
                  );
                  expect(
                    painted.bottom,
                    lessThanOrEqualTo(destinationBounds.bottom),
                  );
                }
              }
              expect(labelHeights, hasLength(1));

              // Inspect the composed pixels, not just the theme property:
              // the rail must paint top to bottom without escaping its slot.
              final image = await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(frame),
                );
                final image = await boundary.toImage();
                try {
                  return await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  );
                } finally {
                  image.dispose();
                }
              });
              int pixel(int x, int y) {
                final at = (y * size.width.toInt() + x) * 4;
                return (image!.getUint8(at + 3) << 24) |
                    (image.getUint8(at) << 16) |
                    (image.getUint8(at + 1) << 8) |
                    image.getUint8(at + 2);
              }

              for (var y = 0; y < size.height.toInt(); y++) {
                expect(
                  pixel(0, y),
                  theme.colorScheme.surfaceContainer.toARGB32(),
                  reason: 'rail background at y=$y',
                );
                expect(
                  pixel(80, y),
                  theme.colorScheme.surface.toARGB32(),
                  reason: 'paint outside the 80 dp rail at y=$y',
                );
                expect(pixel(83, y), theme.colorScheme.surface.toARGB32());
              }
            }
          }
        }
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('app resizes between phone, landscape and Windows widths '
        '${dark ? "dark" : "light"}', (tester) async {
      await loadWideNavigationFonts(tester);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefs = LocalPreferences.memory()
        ..themeMode = dark ? ThemeMode.dark : ThemeMode.light;
      final store = RecipeStore(
        FakeRepository([
          for (var index = 0; index < 12; index++)
            recipe(
              'rail-recipe-$index',
              title: 'Vegetable supper ${index + 1}',
            ),
        ]),
        prefs,
      );
      await store.initialize();
      addTearDown(() {
        store.dispose();
        prefs.dispose();
      });
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: _Platform(true),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      final phoneTheme = Theme.of(tester.element(find.byType(NavigationBar)));
      final phoneColor = phoneTheme.navigationBarTheme.backgroundColor;
      expect(phoneColor, phoneTheme.colorScheme.surfaceContainer);
      for (final size in [
        const Size(844, 390),
        const Size(1440, 900),
        const Size(390, 844),
        const Size(320, 720),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (size.width >= 600) {
          expect(find.byType(NavigationBar), findsNothing);
          final rail = find.byType(NavigationRail);
          expect(rail, findsOneWidget);
          expect(tester.getRect(rail), Rect.fromLTWH(0, 0, 80, size.height));
          expect(
            Theme.of(tester.element(rail)).navigationRailTheme.backgroundColor,
            phoneColor,
          );
        } else {
          expect(find.byType(NavigationRail), findsNothing);
          expect(find.byType(NavigationBar), findsOneWidget);
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
