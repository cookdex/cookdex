import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'editor_test.dart' show reveal, enterFieldText;
import 'support/polish_fixtures.dart';

void main() {
  test(
    'recipe text preference persists and composes system text scaling',
    () async {
      final root = await Directory.systemTemp.createTemp('cookdex-text-size-');
      try {
        final prefs = await LocalPreferences.load('${root.path}/ui.json');
        prefs.setRecipeTextSize(RecipeTextSize.extraLarge);
        await prefs.flush();
        prefs.dispose();
        await prefs.flush();
        final reloaded = await LocalPreferences.load('${root.path}/ui.json');
        expect(reloaded.recipeTextSize, RecipeTextSize.extraLarge);
        expect(
          const RecipeTextScaler(TextScaler.linear(1.5), 1.3).scale(16),
          closeTo(31.2, .001),
        );
        reloaded.dispose();
        await reloaded.flush();
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'touch outside dismisses focus; suggestion chips keep it and IME hide clears it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final prefs = LocalPreferences.memory();
      final store = RecipeStore(PolishRepository(), prefs);
      await store.initialize();
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: ShellPlatform(),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      final search = find.byKey(const Key('recipe-search'));
      await tester.tap(search);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        true,
      );
      await tester.tap(find.text('Favorites'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: search, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        false,
      );
      await tester.tap(find.text('Family pork supper').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit recipe'));
      await tester.pumpAndSettle();
      final tag = find.byKey(const ValueKey('tag-input'));
      await reveal(tester, tag);
      await tester.tap(tag);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      final input = tester.widget<EditableText>(
        find.descendant(of: tag, matching: find.byType(EditableText)),
      );
      await tester.enterText(tag, '');
      await tester.pumpAndSettle();
      // A unit strip always has options, regardless of which tags are already used.
      final unit = find
          .byWidgetPredicate(
            (w) => w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value.endsWith('-unit'),
          )
          .first;
      await reveal(tester, unit);
      await enterFieldText(tester, unit, '');
      await tester.pumpAndSettle();
      final strip = find.byKey(const ValueKey('editor-suggestion-strip'));
      expect(strip, findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'tbsp'));
      await tester.pumpAndSettle();
      final focused = tester.widget<EditableText>(
        find.descendant(of: unit, matching: find.byType(EditableText)),
      );
      expect(focused.focusNode.hasFocus, true);
      expect(strip, findsOneWidget);
      expect(input.focusNode.hasFocus, false);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(focused.focusNode.hasFocus, false);
      expect(strip, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    },
  );
  testWidgets('all shell Snackbars clear expanded Cook controls', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(840, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = LocalPreferences.memory()
      ..setRecipeTextSize(RecipeTextSize.extraLarge);
    final store = RecipeStore(PolishRepository(), prefs);
    await store.initialize();
    await tester.pumpWidget(
      CookdexApp(store: store, platform: ShellPlatform()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family pork supper').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cook'));
    await tester.pumpAndSettle();
    ScaffoldMessenger.of(tester.element(find.byType(RecipeDetail)))
        .showSnackBar(
          const SnackBar(content: Text('Generic shopping / export feedback')),
        );
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            ),
          )
          .bottom,
      lessThan(tester.getRect(find.byType(CookNavigation)).top),
    );
    expect(find.text('Next').hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
  });
  testWidgets('Cards to Compact remeasures tight grid rows', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final prefs = LocalPreferences.memory();
    final store = RecipeStore(PolishRepository(), prefs);
    await store.initialize();
    await tester.pumpWidget(
      CookdexApp(store: store, platform: ShellPlatform()),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(RecipeGridRow).first).height,
      greaterThan(80),
    );
    prefs.setView(RecipeView.compact);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(RecipeGridRow).first).height,
      lessThan(80),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
  });
  testWidgets(
    'actual declarative recipe page paints opaque during predictive Back',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = LocalPreferences.memory();
      final store = RecipeStore(PolishRepository(), prefs);
      await store.initialize();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('pixels'),
          child: CookdexApp(store: store, platform: ShellPlatform()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Family pork supper').first);
      await tester.pumpAndSettle();
      Future<void> gesture(String method, double progress) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/backgesture',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, {
              'touchOffset': <double>[250 * progress, 400],
              'progress': progress,
              'swipeEdge': 0,
            }),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await gesture('startBackGesture', 0);
      await gesture('updateBackGestureProgress', .7);
      final rect = tester.getRect(find.byType(RecipeDetail));
      expect(rect.left, greaterThan(0));
      expect(rect.width, lessThan(390));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('pixels')),
      );
      final pixel = await tester.runAsync(() async {
        final img = await boundary.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
        final offset = (250 * img.width + rect.left.ceil() + 3) * 4;
        final c = Color.fromARGB(
          bytes!.getUint8(offset + 3),
          bytes.getUint8(offset),
          bytes.getUint8(offset + 1),
          bytes.getUint8(offset + 2),
        );
        img.dispose();
        return c;
      });
      expect(
        pixel,
        Theme.of(tester.element(find.byType(RecipeDetail))).scaffoldBackgroundColor,
      );
      await gesture('cancelBackGesture', 0);
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    },
  );
}
