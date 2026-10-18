import 'dart:io';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

Future<ThemeData> _phoneTheme(WidgetTester tester) async {
  const family = 'EmptyLibraryTestRoboto';
  await tester.runAsync(() async {
    final sdk = Platform.environment['FLUTTER_SDK']!;
    final loader = FontLoader(family);
    for (final weight in ['regular', 'bold']) {
      loader.addFont(
        File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await loader.load();
  });
  final theme = cookdexTheme();
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: family),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
  );
}

void main() {
  for (final width in [320.0, 390.0, 1024.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('empty-library actions at $width dp / $scale text', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = LocalPreferences.memory();
        final store = RecipeStore(FakeRepository([]), preferences);
        await store.initialize();
        addTearDown(store.dispose);
        addTearDown(preferences.dispose);
        var imports = 0, writes = 0, restores = 0, help = 0;
        final theme = await _phoneTheme(tester);
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: RecipesScreen(
                store: store,
                preferences: preferences,
                onOpenRecipe: (_) {},
                onAdd: () => fail('Empty library has direct actions'),
                onActions: (_) {},
                onImport: () => imports++,
                onWrite: () => writes++,
                onRestore: () => restores++,
                onHelp: () => help++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('No recipes caught yet'), findsOneWidget);
        expect(
          find.text(
            'Import one from a photo, link or text, or write your own.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('recipe-search')), findsNothing);
        expect(find.byType(FilterChip), findsNothing);
        expect(find.byType(ActionChip), findsNothing);
        expect(find.byType(FloatingActionButton), findsNothing);
        final import = find.widgetWithText(FilledButton, 'Smart Import');
        final write = find.widgetWithText(OutlinedButton, 'Write a recipe');
        final importRect = tester.getRect(import);
        final writeRect = tester.getRect(write);
        expect(importRect.width, closeTo(writeRect.width, .01));
        expect(importRect.height, greaterThanOrEqualTo(48));
        expect(writeRect.height, greaterThanOrEqualTo(48));
        if (width == 390 && scale == 1 || width >= 1024) {
          expect(importRect.top, writeRect.top);
          expect(importRect.right + 12, closeTo(writeRect.left, .01));
        } else {
          expect(importRect.left, writeRect.left);
          expect(importRect.bottom + 12, closeTo(writeRect.top, .01));
        }
        await tester.ensureVisible(import);
        await tester.pumpAndSettle();
        await tester.tap(import);
        await tester.ensureVisible(write);
        await tester.pumpAndSettle();
        await tester.tap(write);
        for (final label in ['Restore a backup', 'How cookdex works']) {
          final link = find.widgetWithText(TextButton, label);
          expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
          await tester.ensureVisible(link);
          await tester.pumpAndSettle();
          await tester.tap(link);
        }
        expect([imports, writes, restores, help], [1, 1, 1, 1]);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('search appears with first recipe and survives no matches', (
    tester,
  ) async {
    final preferences = LocalPreferences.memory();
    final repository = FakeRepository([]);
    final store = RecipeStore(repository, preferences);
    await store.initialize();
    addTearDown(store.dispose);
    addTearDown(preferences.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: Scaffold(
          body: RecipesScreen(
            store: store,
            preferences: preferences,
            onOpenRecipe: (_) {},
            onAdd: () {},
            onActions: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe-search')), findsNothing);
    repository.changed(recipe('first'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe-search')), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Favorites'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.enterText(find.byKey(const Key('recipe-search')), 'no match');
    await tester.pumpAndSettle();
    expect(find.text('No matching recipes'), findsOneWidget);
    expect(find.byKey(const Key('recipe-search')), findsOneWidget);
    expect(find.text('Restore a backup'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Lemon cake'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
