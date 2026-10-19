import 'package:cookdex/editor_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor, reveal;

void main() {
  for (final profile in [
    ('320', const Size(320, 900), 1.0),
    ('390', const Size(390, 900), 1.0),
    ('320-large', const Size(320, 1100), 2.0),
    ('390-large', const Size(390, 1100), 2.0),
    ('tablet', const Size(1280, 900), 1.0),
  ]) {
    testWidgets(
      '${profile.$1}: package unit and amounts fit before and after activation',
      (tester) async {
        final (c, _, _) = await controller();
        final rows = [
          EditableIngredient(
            amount: '1 1/2',
            unit: '(14 oz) cans',
            name: 'tomatoes',
          ),
          EditableIngredient(
            amount: '6–7',
            unit: '(14 oz) cans',
            name: 'beans',
          ),
        ];
        c.draft.sections.first.rows
          ..clear()
          ..addAll(rows);
        await editor(
          tester,
          c,
          size: profile.$2,
          scale: profile.$3,
          phoneFont: true,
        );
        for (final row in rows) {
          final amount = find.byKey(ValueKey('${row.id}-amount'));
          final unit = find.byKey(ValueKey('${row.id}-unit'));
          final name = find.byKey(ValueKey('${row.id}-name'));
          await reveal(tester, name);
          expect(
            tester.getSize(name).width,
            greaterThan(tester.getSize(unit).width),
          );
          expect(
            tester.getSize(name).width,
            greaterThan(tester.getSize(amount).width),
          );
          for (final field in [amount, unit]) {
            await reveal(tester, field);
            final before = tester.getSize(field);
            final textFinder = find.descendant(
              of: field,
              matching: find.byType(Text),
            );
            final paragraph = tester.renderObject<RenderParagraph>(textFinder);
            final text = tester.widget<Text>(textFinder);
            final painter = TextPainter(
              text: TextSpan(text: text.data, style: text.style),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(profile.$3),
            )..layout();
            expect(
              painter.width,
              lessThanOrEqualTo(paragraph.size.width),
              reason: 'Full value fits without clipping',
            );
            painter.dispose();
            await tester.tap(field);
            await tester.pumpAndSettle();
            final native = find.descendant(
              of: field,
              matching: find.byType(EditableText),
            );
            final input = tester
                .state<EditableTextState>(native)
                .renderEditable;
            expect(
              input.maxScrollExtent,
              0,
              reason: 'Full value fits in the active field',
            );
            expect(tester.getSize(field).width, before.width);
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            expect(tester.getSize(field).width, before.width);
            expect(tester.takeException(), isNull);
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
