import 'package:cookdex/editor_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor, reveal;

Rect _relative(RenderBox child, RenderBox field) =>
    child.localToGlobal(Offset.zero, ancestor: field) & child.size;

void _sameRect(Rect actual, Rect expected, String reason) {
  expect(actual.left, closeTo(expected.left, .5), reason: '$reason left');
  expect(actual.top, closeTo(expected.top, .5), reason: '$reason top');
  expect(actual.width, closeTo(expected.width, .5), reason: '$reason width');
  expect(actual.height, closeTo(expected.height, .5), reason: '$reason height');
}

void main() {
  for (final profile in [
    ('320', const Size(320, 900), 1.0),
    ('412', const Size(412, 900), 1.0),
    ('tablet', const Size(1280, 900), 1.0),
    ('320-large', const Size(320, 1100), 2.0),
    ('412-large', const Size(412, 1100), 2.0),
  ]) {
    testWidgets(
      '${profile.$1}: idle ingredient geometry matches native activation and blur',
      (tester) async {
        final (c, _, _) = await controller();
        final row = EditableIngredient(
          amount: '1 1/2',
          unit: 'cup',
          name: 'Tender green lentils with roasted carrots, fresh garden herbs, finely sliced spring onions and golden potatoes, drained thoroughly before mixing with the other ingredients',
          prepNote: 'Rinse and drain well.',
          showNote: true,
        );
        c.draft.sections.first.rows
          ..clear()
          ..add(row);
        await editor(
          tester,
          c,
          size: profile.$2,
          scale: profile.$3,
          phoneFont: true,
        );
        for (final part in ['name', 'note', 'amount', 'unit']) {
          final outer = find.byKey(ValueKey('${row.id}-$part'));
          await reveal(tester, outer);
          final native = find.descendant(
            of: outer,
            matching: find.byType(EditableText),
          );
          expect(
            native,
            findsNothing,
            reason: '$part starts in the lightweight path',
          );
          final idleText = find.descendant(
            of: outer,
            matching: find.byType(Text),
          );
          expect(idleText, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(idleText);
          final field = tester.renderObject<RenderBox>(outer);
          final size = field.size;
          expect(
            size.height,
            greaterThanOrEqualTo(48),
            reason: '$part hit target',
          );
          final textRect = _relative(paragraph, field);
          expect(
            textRect.left,
            closeTo(12, .5),
            reason: '$part native filled inset',
          );
          expect(
            size.width - textRect.right,
            closeTo(15, .5),
            reason: '$part cursor reservation',
          );
          if (part == 'note') {
            final rowRect = tester.getRect(find.byKey(ValueKey(row.id)));
            expect(
              size.width,
              closeTo(rowRect.width - 16, .5),
              reason: 'Prep note fills the row inside its two 8dp paddings',
            );
          }
          final outline = find.descendant(
            of: outer,
            matching: find.byWidgetPredicate(
              (w) => w is DecoratedBox && w.decoration is ShapeDecoration,
            ),
          );
          expect(outline, findsOneWidget);
          final paintRect = _relative(
            tester.renderObject<RenderBox>(outline),
            field,
          );
          expect(paintRect.top, closeTo(0, .5));
          expect(
            paintRect.height,
            closeTo(paragraph.size.height + 24, .5),
            reason: 'The resting outline uses natural text height, not the 48dp hit footprint',
          );
          final text = tester.widget<Text>(idleText).data!;
          final positions = <int>[
            0,
            for (var i = 1; i < text.length; i++)
              if (text[i - 1] == ' ') i,
            text.length - 1,
          ];
          final glyphRects = <Rect>[];
          for (final index in positions) {
            final box = paragraph
                .getBoxesForSelection(
                  TextSelection(baseOffset: index, extentOffset: index + 1),
                  // RenderParagraph defaults to tight boxes; RenderEditable
                  // uses EditableText's line-spacing-aware selection styles.
                  // Compare the same public box policy without changing either
                  // renderer's font, strut, layout or selection geometry.
                  boxHeightStyle: EditableText.defaultSelectionHeightStyle,
                  boxWidthStyle: EditableText.defaultSelectionWidthStyle,
                )
                .single;
            glyphRects.add(box.toRect().shift(textRect.topLeft));
          }
          if (part == 'name') {
            expect(
              glyphRects.last.top,
              greaterThan(glyphRects.first.top),
              reason: 'The name fixture must exercise actual line wrapping',
            );
          }
          await tester.tap(outer);
          await tester.pumpAndSettle();
          for (final state in ['active', 'unfocused']) {
            if (state == 'unfocused') {
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
            }
            expect(native, findsOneWidget);
            final input = tester
                .state<EditableTextState>(native)
                .renderEditable;
            final currentField = tester.renderObject<RenderBox>(outer);
            expect(
              input.selectionHeightStyle,
              EditableText.defaultSelectionHeightStyle,
            );
            expect(
              input.selectionWidthStyle,
              EditableText.defaultSelectionWidthStyle,
            );
            expect(
              currentField.size.width,
              closeTo(size.width, .5),
              reason: '$part $state field width',
            );
            expect(
              currentField.size.height,
              closeTo(size.height, .5),
              reason: '$part $state field height',
            );
            final inputRect = _relative(input, currentField);
            expect(
              inputRect.width,
              closeTo(textRect.width + 3, .5),
              reason:
                  '$part $state reserves the cursor without changing wrap width',
            );
            for (var i = 0; i < positions.length; i++) {
              final index = positions[i];
              final box = input
                  .getBoxesForSelection(
                    TextSelection(baseOffset: index, extentOffset: index + 1),
                  )
                  .single;
              _sameRect(
                box.toRect().shift(inputRect.topLeft),
                glyphRects[i],
                '$part $state character $index',
              );
            }
            final container = InputDecorator.containerOf(
              tester.element(native),
            );
            expect(container, isNotNull);
            _sameRect(
              _relative(container!, currentField),
              paintRect,
              '$part $state painted outline',
            );
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
