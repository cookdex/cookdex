import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/update_controls.dart';
import 'package:cookdex/ui/recipe_top_button.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/update_checker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'recipe_store_test.dart' show FakeRepository, recipe;
import 'search_ranking_test.dart' show searchScreenshotsRecipes;
import 'update_checker_test.dart' show FakeReleaseSource, releaseJson;

void main() {
  for (final (width, scale) in [(320.0, 1.0), (390.0, 2.0), (1280.0, 1.0)]) {
    for (final view in RecipeView.values) {
      testWidgets(
        'update notice, Top and Add stay separate at $width/$scale/$view',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 844);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final prefs = LocalPreferences.memory()..view = view;
          final store = RecipeStore(
            FakeRepository([
              for (var i = 0; i < 150; i++) recipe('$i', title: 'Recipe $i'),
            ]),
            prefs,
          );
          await store.initialize();
          final controller = UpdateController(
            preferences: prefs,
            source: FakeReleaseSource(),
            installedVersion: () async => '1.9.0',
            startupDelay: Duration.zero,
          );
          await tester.pumpWidget(
            CookdexApp(
              store: store,
              platform: ShellPlatform(),
              importService: ImportFakeService(),
              updates: controller,
            ),
          );
          await tester.pumpAndSettle();
          final scrollable = find
              .descendant(
                of: find.byKey(const PageStorageKey('recipes-scroll')),
                matching: find.byType(Scrollable),
              )
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.viewportDimension * 3);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<RecipeTopButton>(find.byType(RecipeTopButton))
                .visible
                .value,
            true,
          );
          controller.setAutomatic(true);
          await tester.pump(const Duration(milliseconds: 1));
          void separated() {
            final notice = tester.getRect(
              find.byKey(const Key('update-notice')),
            );
            final top = tester.getRect(
              find.byKey(const Key('recipe-top-button')),
            );
            final add = tester.getRect(find.byKey(const Key('add-recipe')));
            expect(notice.overlaps(top), false);
            expect(notice.overlaps(add), false);
            expect(top.overlaps(add), false);
            expect(top.bottom, lessThanOrEqualTo(notice.top));
            expect(add.bottom, lessThanOrEqualTo(notice.top));
          }

          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            separated();
          }
          final drag = await tester.startGesture(tester.getCenter(scrollable));
          await drag.moveBy(const Offset(0, -240));
          for (var i = 0; i < 15; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            separated();
          }
          await drag.up();
          await tester.pump(const Duration(milliseconds: 500));
          for (var i = 0; i < 25; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            separated();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          prefs.dispose();
        },
        semanticsEnabled: false,
      );
    }
  }
  testWidgets(
    'Settings checks on tap, renders notes literally, opens only release page',
    (tester) async {
      final prefs = LocalPreferences.memory();
      const notes = '**Fixes** <b>new</b> [link](https://evil.example)';
      final source = FakeReleaseSource()
        ..result = PublishedRelease.fromJson(releaseJson('v1.9.1', notes));
      final controller = UpdateController(
        preferences: prefs,
        source: source,
        installedVersion: () async => '1.9.0',
      );
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Scaffold(
            body: UpdateSettingsPanel(
              controller: controller,
              openPage: (url) async {
                opened.add(url);
              },
            ),
          ),
        ),
      );
      expect(source.calls, 0);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('cookdex 1.9.1 is available'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('release-notes'))).data,
        'Fixes new link',
      );
      expect(opened, isEmpty);
      await tester.tap(find.text('Open release page'));
      await tester.pumpAndSettle();
      expect(opened, [
        'https://github.com/cookdex/cookdex/releases/tag/v1.9.1',
      ]);
      source.error = const SocketException('offline');
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text(updateCheckError), findsOneWidget);
      expect(find.byKey(const Key('release-notes')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      prefs.dispose();
    },
  );
  testWidgets(
    'automatic notice is nonmodal and dismissal persists; details require tap',
    (tester) async {
      final prefs = LocalPreferences.memory()..checkUpdatesAutomatically = true;
      final controller = UpdateController(
        preferences: prefs,
        source: FakeReleaseSource(),
        installedVersion: () async => '1.9.0',
        startupDelay: Duration.zero,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Scaffold(
            body: const Text('Recipes remain usable'),
            bottomNavigationBar: UpdateNotice(
              controller: controller,
              openPage: (_) async {},
            ),
          ),
        ),
      );
      controller.afterFirstFrame();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(
        tester.getSize(find.byTooltip('Dismiss update')).shortestSide,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Open release page'), findsOneWidget);
      Navigator.of(tester.element(find.byType(UpdateDetails))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dismiss update'));
      await tester.pumpAndSettle();
      expect(find.text('cookdex 1.9.1 is available'), findsNothing);
      expect(prefs.dismissedUpdateVersion, '1.9.1');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      prefs.dispose();
    },
  );
  testWidgets(
    'update checker real-font host states',
    (tester) async {
      await loadSectionCaptureFonts(tester);
      await tester.runAsync(() async {
        final fonts = FontLoader('Segoe UI');
        for (final name in ['segoeui.ttf', 'segoeuib.ttf']) {
          fonts.addFont(
            File('${Platform.environment['WINDIR']}/Fonts/$name')
                .readAsBytes()
                .then(ByteData.sublistView),
          );
        }
        await fonts.load();
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.sylph.cookdex.dev/platform'),
        (call) async => call.method == 'appVersion' ? '1.9.0+19000' : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.sylph.cookdex.dev/platform'),
          null,
        ),
      );
      debugDisableShadows = false;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const output = '../artifacts/update-checker/screenshots';
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
          final prefs = LocalPreferences.memory()
            ..themeMode = dark ? ThemeMode.dark : ThemeMode.light
            ..recipeTextSize = scale > 1
                ? RecipeTextSize.extraLarge
                : RecipeTextSize.normal;
          final store = RecipeStore(
            FakeRepository(searchScreenshotsRecipes()),
            prefs,
          );
          await store.initialize();
          final source = FakeReleaseSource();
          final controller = UpdateController(
            preferences: prefs,
            source: source,
            installedVersion: () async => '1.9.0+19000',
            startupDelay: Duration.zero,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('update-capture'),
              child: CookdexApp(
                store: store,
                platform: ShellPlatform(),
                importService: ImportFakeService(),
                updates: controller,
              ),
            ),
          );
          await tester.pumpAndSettle();
          Future<void> shot(String state) async {
            final name = '${dark ? 'dark' : 'light'}-$profile-$state.png';
            expect(tester.takeException(), isNull, reason: name);
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('update-capture')),
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
              'state': state,
            });
          }

          await tester.tap(find.text('Settings').last);
          await tester.pumpAndSettle();
          Future<void> reveal() async {
            final scrollable = find
                .descendant(
                  of: find.byKey(const PageStorageKey('settings')),
                  matching: find.byType(Scrollable),
                )
                .first;
            final position = tester.state<ScrollableState>(scrollable).position;
            await tester.scrollUntilVisible(
              find.byKey(const Key('check-updates')),
              250,
              scrollable: scrollable,
            );
            await tester.pumpAndSettle();
            // At normal sizes show the whole About card; large text shows the controls first.
            if (scale == 1) position.jumpTo(position.maxScrollExtent);
            final notesScroll = find.descendant(
              of: find.byType(UpdateDetails),
              matching: find.byType(Scrollable),
            );
            if (notesScroll.evaluate().isNotEmpty) {
              tester.state<ScrollableState>(notesScroll).position.jumpTo(0);
            }
            await tester.pumpAndSettle();
          }

          await reveal();
          if (profile != 'windows') await shot('settings');
          if (profile == 'normal-phone' || profile == 'largest-phone') {
            source.pending = Completer<PublishedRelease?>();
            final checking = controller.check();
            await tester.pump();
            await reveal();
            await shot('checking');
            source.pending!.complete(
              PublishedRelease.fromJson(releaseJson('v1.9.0')),
            );
            await checking;
            source.pending = null;
          }
          source.result = PublishedRelease.fromJson(releaseJson('v1.9.0'));
          await controller.check();
          await tester.pumpAndSettle();
          await reveal();
          if (profile != 'windows') await shot('current');
          source.result = PublishedRelease.fromJson(
            releaseJson(
              'v1.9.1',
              'Small improvements for everyday cooking.\n\n• Clearer recipe search results\n• Fixes for the recipe editor',
            ),
          );
          await controller.check();
          await tester.pumpAndSettle();
          await reveal();
          await shot('available');
          source.error = const SocketException('offline');
          await controller.check();
          await tester.pumpAndSettle();
          await reveal();
          if (profile != 'windows') await shot('error');
          source.error = null;
          prefs.lastUpdateCheckMs = null;
          controller.setAutomatic(true);
          await tester.tap(find.text('Recipes').last);
          await tester.pumpAndSettle();
          expect(find.byType(Dialog), findsNothing);
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.text('cookdex 1.9.1 is available'), findsOneWidget);
          await shot('notice');
          if (profile == 'normal-phone' || profile == 'largest-phone') {
            await tester.tap(find.text('View'));
            await tester.pumpAndSettle();
            await shot('details-sheet');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          prefs.dispose();
        }
      }
      await tester.runAsync(
        () => File(
          '$output/manifest.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest)),
      );
      debugDefaultTargetPlatformOverride = null;
      debugDisableShadows = true;
    },
    skip: !const bool.fromEnvironment('COOKDEX_UPDATE_SCREENSHOTS'),
    semanticsEnabled: false,
  );
}
