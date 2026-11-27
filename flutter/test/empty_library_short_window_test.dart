import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'final_pass_screenshots_test.dart' show ScreenshotPlatform;
import 'fixtures/wide_navigation_test_support.dart';
import 'import_test.dart' show ImportFakeService;
import 'recipe_store_test.dart' show FakeRepository;
import 'round3_device_frame.dart';

void main() {
  for (final (profile, size, scale, android) in [
    ('phone', const Size(390, 844), 1.0, true),
    ('phone-large-text', const Size(390, 844), 1.5, true),
    ('tablet-portrait', const Size(800, 1280), 1.5, true),
    ('short-android-window', const Size(844, 390), 1.5, true),
    ('short-windows', const Size(844, 390), 1.5, false),
    ('split-windows', const Size(640, 320), 1.5, false),
    ('narrow-windows', const Size(390, 390), 1.5, false),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'empty welcome fits or scrolls $profile ${dark ? 'dark' : 'light'}',
        (tester) async {
          await loadWideNavigationFonts(tester, desktop: !android);
          final previousPlatform = debugDefaultTargetPlatformOverride;
          final previousShadows = debugDisableShadows;
          debugDefaultTargetPlatformOverride = android
              ? TargetPlatform.android
              : TargetPlatform.windows;
          debugDisableShadows = false;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          tester.view.display.size = profile == 'short-android-window'
              ? const Size(1280, 800)
              : size;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          if (android) round3SystemInsets(tester);
          final preferences = LocalPreferences.memory();
          preferences.themeMode = dark ? ThemeMode.dark : ThemeMode.light;
          preferences.recipeTextSize = scale > 1
              ? RecipeTextSize.large
              : RecipeTextSize.normal;
          final store = RecipeStore(FakeRepository([]), preferences);
          await store.initialize();
          try {
            final app = CookdexApp(
              store: store,
              platform: ScreenshotPlatform(android),
              importService: ImportFakeService(),
            );
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('empty-welcome-capture'),
                child: android
                    ? round3DeviceFrame(
                        app,
                        dark: dark,
                        tablet: size.width >= 600,
                      )
                    : app,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.text('No recipes caught yet'), findsOneWidget);
            expect(find.byKey(const Key('recipe-search')), findsNothing);

            Future<void> capture(String state) async {
              if (Platform.environment['EMPTY_WELCOME_GALLERY'] != '1') return;
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const Key('empty-welcome-capture')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final directory =
                    Platform.environment['EMPTY_WELCOME_GALLERY_DIR'] ??
                    '../artifacts/shopping-and-sharing/phone-orientation/empty-welcome';
                final file = File(
                  '$directory/$profile-${dark ? 'dark' : 'light'}-$state.png',
                );
                await file.parent.create(recursive: true);
                await file.writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }

            await capture('initial');
            for (final label in [
              'Smart Import',
              'Write a recipe',
              'Smart Create',
              'Restore a backup',
              'How cookdex works',
            ]) {
              final action = find.ancestor(
                of: find.text(label),
                matching: find.byWidgetPredicate(
                  (widget) => widget is ButtonStyleButton,
                ),
              );
              expect(action, findsOneWidget);
              expect(tester.getSize(action).height, greaterThanOrEqualTo(48));
              await tester.ensureVisible(action);
              await tester.pumpAndSettle();
              expect(action.hitTestable(), findsOneWidget, reason: label);
              expect(tester.takeException(), isNull, reason: label);
            }
            await capture('last-actions');
            final screen = tester.state<RecipesScreenState>(
              find.byType(RecipesScreen),
            );
            screen.scrollToTop();
            await tester.pumpAndSettle();
            expect(
              find.text('No recipes caught yet').hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            store.dispose();
            preferences.dispose();
            tester.view.reset();
            tester.view.display.reset();
            tester.platformDispatcher.clearTextScaleFactorTestValue();
            debugDefaultTargetPlatformOverride = previousPlatform;
            debugDisableShadows = previousShadows;
          }
        },
      );
    }
  }
}
