import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor, reveal;

Future<TextField> activate(WidgetTester tester, String key) async {
  final outer = find.byKey(ValueKey(key));
  await reveal(tester, outer);
  await tester.tap(outer);
  await tester.pumpAndSettle();
  return tester.widget<TextField>(
    find.descendant(of: outer, matching: find.byType(TextField)),
  );
}

void main() {
  testWidgets(
    'prose capitalizes sentences while structured fields stay literal',
    (tester) async {
      final (c, _, _) = await controller();
      await editor(tester, c);
      for (final key in ['title', 'description', 'notes']) {
        final field = await activate(tester, key);
        expect(field.textCapitalization, TextCapitalization.sentences);
      }
      for (final key in [
        'servings',
        'prep',
        'cook',
        'total',
        '${c.draft.sections.first.rows.first.id}-name',
        '${c.draft.sections.first.rows.first.id}-unit',
      ]) {
        final field = await activate(tester, key);
        expect(field.textCapitalization, TextCapitalization.none);
      }
      final step = await activate(tester, '${c.draft.steps.first.id}-text');
      expect(step.textCapitalization, TextCapitalization.sentences);
      expect(step.autocorrect, isTrue);
      expect(step.enableSuggestions, isTrue);
    },
  );

  testWidgets('to taste replaces the amount and retains field focus', (
    tester,
  ) async {
    final (c, _, _) = await controller();
    final row = c.draft.sections.first.rows.first..amount = '1/2-3/4';
    await editor(tester, c);
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetViewInsets);
    final field = await activate(tester, '${row.id}-amount');
    expect(field.keyboardType, TextInputType.text);
    expect(find.text('to taste'), findsOneWidget);
    expect(find.text('as needed'), findsNothing);
    await tester.tap(find.text('to taste'));
    await tester.pumpAndSettle();
    expect(row.amount, 'to taste');
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.selection.baseOffset, 8);
    expect(find.text('abc'), findsNothing);
  });

  for (final profile in [
    (320.0, 1.0),
    (390.0, 1.0),
    (390.0, 2.0),
    (1280.0, 1.0),
  ]) {
    testWidgets('Makes and ordered times wrap at ${profile.$1}/${profile.$2}', (
      tester,
    ) async {
      final (c, _, _) = await controller();
      await editor(
        tester,
        c,
        size: Size(profile.$1, 1100),
        scale: profile.$2,
        phoneFont: true,
      );
      final makes = find.byKey(const ValueKey('field-servings'));
      final times = find.byKey(const ValueKey('recipe-times'));
      await reveal(tester, makes);
      expect(tester.getSize(makes).width, tester.getSize(times).width);
      final prep = tester.getRect(find.byKey(const ValueKey('field-prep')));
      final cook = tester.getRect(find.byKey(const ValueKey('field-cook')));
      final total = tester.getRect(find.byKey(const ValueKey('field-total')));
      expect(prep.top, lessThanOrEqualTo(cook.top));
      expect(cook.top, lessThanOrEqualTo(total.top));
      expect(tester.takeException(), isNull);
    });
  }
}
