import 'dart:async';
import 'dart:convert';

import 'package:cookdex/editor_model.dart';
import 'package:cookdex/ingredient_display.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor, reveal;

void main() {
  testWidgets('amount field accepts fractions and range separators unchanged', (
    tester,
  ) async {
    final (c, _, _) = await controller();
    final row = c.draft.sections.single.rows.single;
    await editor(tester, c);
    final field = find.byKey(ValueKey('${row.id}-amount'));
    await reveal(tester, field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: field,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(input).keyboardType, TextInputType.text);
    for (final text in ['1/2-3/4', '1 1/2–2', '2—3', '2 to 3']) {
      await tester.enterText(input, text);
      expect(row.amount, text);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  const range = Amount.range(
    lowerNumerator: 1,
    lowerDenominator: 2,
    upperNumerator: 3,
    upperDenominator: 2,
  );

  test(
    'draft recovery retains exact range and unsaved raw edits separately',
    () {
      final row = EditableIngredient(
        amount: '1/2–1 1/2',
        originalText: '1/2–1 1/2',
        originalAmount: range,
        unit: 'cup',
        name: 'flour',
      );
      EditableIngredient reopen() => EditableIngredient.fromJson(
        jsonDecode(jsonEncode(row.toJson())) as Map<String, dynamic>,
      );
      expect(reopen().canonical('').amount, range);
      expect(reopen().amountInput, isNull);
      row.amount = '3/4 - 2';
      expect(reopen().originalAmount, range);
      expect(reopen().amountInput, '3/4 - 2');
      row.amount = row.originalText!;
      expect(reopen().amountInput, isNull);
    },
  );

  test('ranges pluralize count units from their upper endpoint', () {
    for (final entry in {
      'cup': 'cups',
      'clove': 'cloves',
      'can': 'cans',
      'pinch': 'pinches',
      'g': 'g',
    }.entries) {
      Ingredient ingredient(Amount amount) => Ingredient(
        amount: amount,
        unit: entry.key,
        name: 'ingredient',
        prepNote: '',
        optional: false,
        section: '',
      );
      expect(displayIngredientUnit(ingredient(range)), entry.value);
      expect(
        displayIngredientUnit(
          ingredient(
            const Amount.range(
              lowerNumerator: 1,
              lowerDenominator: 2,
              upperNumerator: 1,
              upperDenominator: 1,
            ),
          ),
        ),
        entry.key,
      );
    }
  });

  test(
    'reversed range errors retain entered text and clear on correction',
    () async {
      final (editor, repo, _) = await controller();
      editor.draft.title = 'Synthetic range';
      final row = editor.draft.sections.single.rows.single;
      row.name = 'flour';
      row.amount = '2–1';
      // A core validation error is presented verbatim, with the draft intact.
      repo.normalizeGate = Completer<RecipeFields>();
      final saving = editor.save();
      repo.normalizeGate!.completeError(
        const ServiceError(
          code: ErrorCode.validation,
          message: 'Put the smaller quantity first in a range.',
        ),
      );
      expect(await saving, isNull);
      expect(editor.draft.error, 'Put the smaller quantity first in a range.');
      expect(row.amount, '2–1');
      row.amount = '1–2';
      editor.changed();
      expect(editor.draft.error, isNull);
      expect(editor.draft.amountInputs(), ['1–2']);
    },
  );
}
