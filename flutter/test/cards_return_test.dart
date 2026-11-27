import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/app_platform.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/recipe_grid.dart';

import 'dart:typed_data';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'back_navigation_audit_test.dart' show gesture;
import '../integration_test/performance/deep_fixture.dart';

import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/pixel_scroll.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

class _Platform extends AppPlatform {
  @override
  bool get isAndroid => true;
  @override
  Future<void> backgroundTask() async {}
  @override
  Future<void> openSource(String value) async {}
  @override
  Future<Uint8List?> pickRecipeZip() async => null;
  @override
  Future<String> privateRoot() async => throw UnimplementedError();
  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
  @override
  Future<ColorScheme?> wallpaperColorScheme({
    Brightness brightness = Brightness.dark,
  }) async => null;
}

void main() {
  for (final systemBack in [false, true]) {
    testWidgets(
      'Actual app Cards stay the same after repeated open and Back (system=$systemBack)',
      (tester) async {
        await loadSectionCaptureFonts(tester);

        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        final prefs = LocalPreferences.memory()..view = RecipeView.cards;
        final store = RecipeStore(
          FakeRepository([
            for (var i = 0; i < 100; i++)
              Recipe(
                id: '$i',
                favorite: false,
                revision: 1,
                createdAt: '2026-01-01',
                updatedAt: '2026-01-01',
                fields: scaleRecipeFields(i),
              ),
          ]),
          prefs,
        );
        await store.initialize();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          store.dispose();
          prefs.dispose();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          CookdexApp(store: store, platform: _Platform()),
        );
        await tester.pumpAndSettle();
        for (var i = 0; i < 12; i++) {
          if (i > 3) {
            await tester.fling(
              find.byKey(const PageStorageKey('recipes-scroll')),
              const Offset(0, -400),
              5200,
            );
            await tester.pumpAndSettle();
          }
          final rows = find.byWidgetPredicate(
            (w) =>
                w.runtimeType.toString() == '_RecipeRow' &&
                w.key is ValueKey<String>,
          );
          final row = rows
              .evaluate()
              .map((e) => find.byWidget(e.widget))
              .firstWhere((f) {
                final r = tester.getRect(f);
                return r.top > 180 && r.bottom < 720;
              });
          final key = tester.widget(row).key!;
          final before = tester.getRect(row);
          List<Rect> slots() {
            final ro = tester.renderObject(
              find.descendant(
                of: find.byKey(key),
                matching: find.byType(RecipeCardContent),
              ),
            );
            final result = <Rect>[];
            ro.visitChildren((r) {
              final b = r as RenderBox;
              result.add(
                b.localToGlobal(
                      Offset.zero,
                      ancestor: tester.renderObject(find.byKey(key)),
                    ) &
                    b.size,
              );
            });
            return result;
          }

          final beforeSlots = slots();
          final g = await tester.startGesture(
            before.centerLeft + const Offset(25, 0),
          );
          await tester.pump(Duration(milliseconds: i.isEven ? 120 : 10));
          await tester.pump();
          expect(
            tester.getRect(find.byKey(key)),
            before,
            reason: 'pressed iteration$i',
          );
          await g.up();
          await tester.pumpAndSettle();
          expect(find.byType(RecipeDetail), findsOneWidget);
          if (systemBack) {
            if (i.isEven) {
              await tester.binding.handlePopRoute();
            } else {
              await gesture(tester, 'startBackGesture', 0);
              await gesture(tester, 'updateBackGestureProgress', .65);
              await gesture(tester, 'commitBackGesture');
            }
          } else {
            await tester.tap(find.byTooltip('Back to recipes').last);
          }
          for (var frame = 0; frame < 40; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              slots(),
              beforeSlots,
              reason: 'slots frame$frame iteration$i',
            );
          }

          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.byKey(key)),
            before,
            reason: 'returned iteration$i',
          );
          expect(slots(), beforeSlots, reason: 'slots returned iteration$i');
        }
      },
      semanticsEnabled: false,
    );
  }

  for (final scrolled in [false, true]) {
    for (final wide in [false, true]) {
      testWidgets(
        'Cards return keeps geometry (scrolled=$scrolled, wide=$wide)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = wide
              ? const Size(1024, 768)
              : const Size(390, 844);
          final preferences = LocalPreferences.memory()
            ..view = RecipeView.cards;
          final store = RecipeStore(
            FakeRepository([
              for (var i = 0; i < 100; i++)
                recipe(
                  '$i',
                  title: 'Garden vegetable soup number $i',
                  description: 'A warming bowl with seasonal vegetables and a lemon dressing.',
                ),
            ]),
            preferences,
          );
          final controller = PixelScrollController();
          final navigator = GlobalKey<NavigatorState>();
          await store.initialize();
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            controller.dispose();
            store.dispose();
            preferences.dispose();
            tester.view.resetDevicePixelRatio();
            tester.view.resetPhysicalSize();
          });
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
              home: Scaffold(
                body: RecipesScreen(
                  store: store,
                  preferences: preferences,
                  controller: controller,
                  onOpenRecipe: (id) => navigator.currentState!.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(
                        body: Center(child: Text('Opened recipe')),
                      ),
                    ),
                  ),
                  onActions: (_) {},
                  onAdd: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (scrolled) {
            await tester.fling(
              find.byKey(const PageStorageKey('recipes-scroll')),
              const Offset(0, -600),
              5200,
            );
            await tester.pumpAndSettle();
          }
          final candidates = find.byWidgetPredicate(
            (w) =>
                w.runtimeType.toString() == '_RecipeRow' &&
                w.key is ValueKey<String>,
          );
          final row = candidates
              .evaluate()
              .map((e) => find.byWidget(e.widget))
              .firstWhere((f) {
                final r = tester.getRect(f);
                return r.top > 180 && r.bottom < 700;
              });
          final key = tester.widget(row).key!;
          final initial = tester.getRect(row);
          final offset = controller.offset;
          final press = await tester.startGesture(
            initial.centerLeft + const Offset(30, 0),
          );
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump();
          expect(
            tester.getRect(find.byKey(key)),
            initial,
            reason: 'Press must not change card layout',
          );
          await press.up();
          await tester.pumpAndSettle();
          expect(find.text('Opened recipe'), findsOneWidget);
          navigator.currentState!.pop();
          await tester.pumpAndSettle();
          expect(controller.offset, offset);
          expect(
            tester.getRect(find.byKey(key)),
            initial,
            reason: 'Returning must restore the exact card layout',
          );
          expect(tester.takeException(), isNull);
        },
        semanticsEnabled: false,
      );
    }
  }
}
