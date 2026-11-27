import 'dart:async';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'recipe_store_test.dart' show FakeRepository, recipe;

void main() {
  for (final detail in [false, true]) {
    testWidgets(
      'star paints before save and rolls back with message, detail=$detail',
      (tester) async {
        final prefs = LocalPreferences.memory();
        final repo = FakeRepository([
          for (var i = 0; i < 500; i++) recipe('r$i', title: 'Soup $i'),
        ]);
        final store = RecipeStore(repo, prefs);
        await store.initialize();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          prefs.dispose();
        });
        await tester.pumpWidget(
          CookdexApp(
            store: store,
            platform: ShellPlatform(),
            importService: ImportFakeService(),
          ),
        );
        await tester.pumpAndSettle();
        if (detail) {
          await tester.tap(find.text('Soup 0').first);
          await tester.pumpAndSettle();
        }
        final gate = repo.favoriteGate = Completer<void>();
        await tester.tap(
          detail
              ? find.byTooltip('Favorite recipe')
              : find.bySemanticsLabel('Favorite Soup 0'),
        );
        await tester.pump();
        expect(
          detail
              ? find.byTooltip('Unfavorite recipe')
              : find.bySemanticsLabel('Unfavorite Soup 0'),
          findsOneWidget,
        );
        gate.completeError(StateError('Synthetic save failure'));
        await tester.pumpAndSettle();
        expect(
          detail
              ? find.byTooltip('Favorite recipe')
              : find.bySemanticsLabel('Favorite Soup 0'),
          findsOneWidget,
        );
        expect(find.text('Could not update favorite'), findsOneWidget);
      },
    );
  }
}
