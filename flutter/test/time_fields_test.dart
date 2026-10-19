import 'dart:typed_data';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart'
    show
        EditorFake,
        controller,
        editor,
        field,
        fieldDecoration,
        enterFieldText,
        reveal;

const timeConfigurations = [
  ('small-phone', Size(320, 800), 1.0),
  ('normal-phone', Size(390, 844), 1.0),
  ('largest-phone', Size(390, 844), 2.0),
  ('tablet-landscape', Size(1280, 800), 1.0),
];
const timeLabels = ['Prep time', 'Cook time', 'Total time'];
const timeKeys = ['prep', 'cook', 'total'];

Future<(EditorController, RecipeStore)> timeController({
  required bool imported,
  required bool filled,
}) async {
  if (!imported) {
    final (c, _, store) = await controller();
    c.draft.title = 'Golden tortillas';
    c.draft.prepTime = filled ? '15 min' : '';
    c.draft.cookTime = filled ? '20 min' : '';
    c.draft.totalTime = filled ? '35 min' : '';
    return (c, store);
  }
  final store = RecipeStore(EditorFake([]), LocalPreferences.memory());
  await store.initialize();
  final c = await EditorController.create(
    store: store,
    storage: MemoryDraftStorage(),
    imported: Candidate(
      recipe: Recipe(
        id: 'synthetic-time-import',
        favorite: false,
        revision: 1,
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
        fields: RecipeFields(
          title: 'Golden tortillas',
          description: '',
          servings: '4 servings',
          prepTime: filled ? '15 min' : '',
          cookTime: filled ? '20 min' : '',
          totalTime: filled ? '35 min' : '',
          source: '',
          tags: [],
          notes: '',
          ingredients: [],
          steps: ['Mix and cook.'],
        ),
      ),
      warnings: [],
      ingredientSources: [],
      aiReview: AiReview(
        guessedFields: const ['totalTime'],
        guessedSteps: Uint32List(0),
      ),
    ),
  );
  addTearDown(() {
    c.dispose();
    store.dispose();
  });
  return (c, store);
}

Finder timeBox(String key) => find.byKey(ValueKey('field-$key'));

void main() {
  for (final config in timeConfigurations) {
    for (final imported in [false, true]) {
      testWidgets(
        '${config.$1} ${imported ? 'import' : 'editor'} time geometry',
        (tester) async {
          final (c, store) = await timeController(
            imported: imported,
            filled: false,
          );
          if (config.$3 == 2) {
            store.preferences.setRecipeTextSize(RecipeTextSize.extraLarge);
          }
          await editor(
            tester,
            c,
            size: config.$2,
            scale: config.$3,
            phoneFont: true,
          );
          expect(
            find.text('Review import'),
            imported ? findsOneWidget : findsNothing,
          );
          await reveal(tester, find.byKey(const ValueKey('recipe-times')));
          final heights = [
            for (final key in timeKeys) tester.getSize(timeBox(key)).height,
          ];
          expect(
            heights.toSet().length,
            1,
            reason: 'All three empty controls match',
          );
          if (config.$3 == 1 && config.$2.width > 320) {
            expect(
              {for (final key in timeKeys) tester.getTopLeft(timeBox(key)).dy}
                  .length,
              1,
              reason: 'Ordinary phone and tablet text fits one time row',
            );
          }
          for (var i = 0; i < timeLabels.length; i++) {
            final target = field(timeLabels[i]);
            await reveal(tester, target);
            final decoration = fieldDecoration(tester, target);
            expect(decoration.labelText, timeLabels[i]);
            expect(decoration.hintText, isNull);
            expect(
              decoration.floatingLabelBehavior,
              FloatingLabelBehavior.always,
            );
            await tester.tap(target);
            await tester.pumpAndSettle();
            expect(tester.getSize(timeBox(timeKeys[i])).height, heights[i]);
            const longTime =
                '30 minutes, plus overnight chilling and resting before cooking';
            await enterFieldText(tester, target, longTime);
            await tester.pumpAndSettle();
            final active = tester.widget<TextField>(target);
            expect(active.maxLines, 1);
            expect(active.controller!.text, longTime);
            final editable = find.descendant(
              of: target,
              matching: find.byType(EditableText),
            );
            final horizontal = find.descendant(
              of: editable,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.right,
              ),
            );
            expect(horizontal, findsOneWidget);
            expect(
              tester
                  .state<ScrollableState>(horizontal)
                  .position
                  .maxScrollExtent,
              greaterThan(0),
            );
            expect(tester.getSize(timeBox(timeKeys[i])).height, heights[i]);
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            expect(tester.getSize(timeBox(timeKeys[i])).height, heights[i]);
          }
          expect(c.draft.prepTime, contains('overnight'));
          expect(c.draft.cookTime, contains('overnight'));
          expect(c.draft.totalTime, contains('overnight'));
          if (imported) {
            await reveal(tester, find.text('Total time: AI guess'));
            expect(find.text('Total time: AI guess'), findsOneWidget);
            expect(
              find.descendant(
                of: timeBox('total'),
                matching: find.text('Total time: AI guess'),
              ),
              findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
