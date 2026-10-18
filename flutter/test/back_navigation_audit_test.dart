import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/smart_settings_screen.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/import_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService, candidate;
import 'support/polish_fixtures.dart';
import 'editor_test.dart' show reveal, enterFieldText;

Future<void> gesture(
  WidgetTester tester,
  String method, [
  double? progress,
]) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        progress == null
            ? null
            : <String, dynamic>{
                'touchOffset': <double>[5 + 250 * progress, 300],
                'progress': progress,
                'swipeEdge': 0,
              },
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

Future<void> back(WidgetTester tester, bool predictive) async {
  if (predictive) {
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .65);
    await gesture(tester, 'commitBackGesture');
  } else {
    await tester.binding.handlePopRoute();
  }
  await tester.pumpAndSettle();
}

Future<LocalPreferences> host(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final prefs = LocalPreferences.memory();
  final store = RecipeStore(PolishRepository(), prefs);
  await store.initialize();
  await tester.pumpWidget(
    CookdexApp(
      store: store,
      platform: ShellPlatform(),
      importService: ImportFakeService()
        ..result = ImportDiscovery(
          candidates: [candidate('incoming', 'Imported soup')],
        ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
  });
  return prefs;
}

void main() {
  testWidgets('Back during a tab fade previews only current tab and Recipes', (
    tester,
  ) async {
    await host(tester, 390);
    await tester.tap(find.text('Family pork supper').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shopping list').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .65);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(ShoppingScreen), findsOneWidget);
    expect(find.byType(RecipeDetail), findsOneWidget);
    await gesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.byType(ShoppingScreen), findsOneWidget);
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .4);
    // A new destination invalidates the in-flight gesture, without popping it.
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await back(tester, true);
    expect(find.byType(RecipeDetail), findsOneWidget);
  });
  for (final predictive in [false, true]) {
    testWidgets(
      'shopping menu and categories return to their origin ($predictive)',
      (tester) async {
        await host(tester, 390);
        await tester.tap(find.text('Shopping list').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Shopping list options'));
        await tester.pumpAndSettle();
        await back(tester, predictive);
        expect(find.byType(ShoppingScreen), findsOneWidget);
        expect(find.text('Categories'), findsNothing);
        await tester.tap(find.byTooltip('Shopping list options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Categories'));
        await tester.pumpAndSettle();
        expect(find.text('Categories'), findsOneWidget);
        await back(tester, predictive);
        expect(find.byType(ShoppingScreen), findsOneWidget);
        await back(tester, predictive);
        expect(find.byType(ShoppingScreen), findsNothing);
      },
    );
    testWidgets(
      'import review returns to retained input then library ($predictive)',
      (tester) async {
        await host(tester, 390);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Smart Import'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'source for soup');
        await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
        await tester.pumpAndSettle();
        expect(find.text('Review import'), findsOneWidget);
        await back(tester, predictive);
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(find.byType(ImportScreen), findsOneWidget);
        expect(find.text('source for soup'), findsOneWidget);
        await back(tester, predictive);
        expect(find.byType(ImportScreen), findsNothing);
      },
    );
    testWidgets(
      'visible overlays, scale and Cook take Back in order ($predictive)',
      (tester) async {
        await host(tester, 390);
        await tester.tap(find.text('Family pork supper').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cook'));
        await tester.pumpAndSettle();
        final scale = find.byKey(const Key('recipe-scale-toggle'));
        await reveal(tester, scale);
        await tester.tap(scale);
        await tester.pumpAndSettle();
        await back(tester, predictive);
        expect(find.byType(RecipeDetail), findsOneWidget);
        expect(find.text('Cooking'), findsOneWidget);
        final context = tester.element(find.byType(RecipeDetail));
        showDialog<void>(
          context: context,
          builder: (_) => const AlertDialog(title: Text('Transient dialog')),
        );
        await tester.pumpAndSettle();
        await back(tester, predictive);
        expect(find.text('Transient dialog'), findsNothing);
        expect(find.byType(RecipeDetail), findsOneWidget);
        showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          builder: (_) =>
              const SizedBox(height: 150, child: Text('Transient sheet')),
        );
        await tester.pumpAndSettle();
        await back(tester, predictive);
        expect(find.text('Transient sheet'), findsNothing);
        expect(find.byType(RecipeDetail), findsOneWidget);
        await back(tester, predictive);
        expect(find.byType(RecipeDetail), findsNothing);
      },
    );
    testWidgets(
      'editor and confirmation never pop underlying recipe ($predictive)',
      (tester) async {
        await host(tester, 390);
        await tester.tap(find.text('Family pork supper').first);
        await tester.pumpAndSettle();
        final detail = tester.element(find.byType(RecipeDetail));
        await tester.tap(find.byTooltip('Edit recipe'));
        await tester.pumpAndSettle();
        await enterFieldText(
          tester,
          find.byKey(const ValueKey('title')),
          'Unsaved title',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await back(tester, predictive);
        expect(find.text('Discard changes?'), findsOneWidget);
        await back(tester, predictive);
        expect(find.text('Discard changes?'), findsNothing);
        expect(find.byType(RecipeEditor), findsOneWidget);
        await back(tester, predictive);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(RecipeDetail)), same(detail));
      },
    );
    testWidgets(
      'Settings subpage returns to Settings then retained recipe ($predictive)',
      (tester) async {
        await host(tester, 390);
        await tester.tap(find.text('Family pork supper').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        await reveal(tester, find.text('Smart Import settings'));
        await tester.tap(find.text('Smart Import settings'));
        await tester.pumpAndSettle();
        expect(find.byType(SmartSettingsScreen), findsOneWidget);
        await back(tester, predictive);
        expect(find.byType(SmartSettingsScreen), findsNothing);
        expect(find.byType(RecipeDetail), findsNothing);
        await back(tester, predictive);
        expect(find.byType(RecipeDetail), findsOneWidget);
      },
    );
    testWidgets('keyboard then search then system exit ($predictive)', (
      tester,
    ) async {
      final prefs = await host(tester, 390);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byKey(const Key('recipe-search')), 'pork');
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await back(tester, predictive);
      expect(prefs.query, 'pork');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        false,
      );
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await back(tester, predictive);
      expect(prefs.query, isEmpty);
      final shellRoute = ModalRoute.of(
        tester.element(find.text('Recipes').last),
      )!;
      expect(shellRoute.popDisposition, RoutePopDisposition.bubble);
      var exited = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') exited = true;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await back(tester, predictive);
      expect(exited, isTrue);
    });
  }
  for (final width in [390.0, 1024.0]) {
    for (final predictive in [false, true]) {
      for (final tab in ['Shopping list', 'Settings']) {
        testWidgets(
          '$tab Back preserves recipe, predictive=$predictive width=$width',
          (tester) async {
            await host(tester, width);
            await tester.tap(find.text('Family pork supper').first);
            await tester.pumpAndSettle();
            await tester.tap(find.text(tab).last);
            await tester.pumpAndSettle();
            await back(tester, predictive);
            expect(find.byType(RecipeDetail), findsOneWidget);
            await back(tester, predictive);
            expect(find.byType(RecipeDetail), findsNothing);
          },
        );
      }
    }
  }
  testWidgets(
    'cancelled tab gesture retains both stacks and previews Recipes',
    (tester) async {
      await host(tester, 390);
      await tester.tap(find.text('Family pork supper').first);
      await tester.pumpAndSettle();
      final detail = tester.element(find.byType(RecipeDetail));
      await tester.tap(find.text('Shopping list').last);
      await tester.pumpAndSettle();
      await gesture(tester, 'startBackGesture', 0);
      await gesture(tester, 'updateBackGestureProgress', .65);
      expect(find.byType(RecipeDetail), findsOneWidget);
      expect(tester.getTopLeft(find.byType(ShoppingScreen)).dx, greaterThan(0));
      await gesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsNothing);
      await tester.tap(find.text('Recipes').last);
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(RecipeDetail)), same(detail));
    },
  );
}
