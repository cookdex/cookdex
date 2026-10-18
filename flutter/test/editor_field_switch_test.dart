import 'package:cookdex/editor_model.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller;

void main() {
  for (final source in ['amount', 'unit', 'name', 'note', 'step']) {
    for (final target in ['amount', 'unit', 'name', 'note', 'step']) {
      testWidgets(
        '$source to untouched $target keeps the keyboard and tap caret',
        (tester) async {
          tester.view.physicalSize = const Size(900, 2400);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final (c, _, _) = await controller();
          final rows = c.draft.sections.first.rows;
          rows.clear();
          rows.addAll(
            List.generate(
              2,
              (_) => EditableIngredient(
                amount: '12345',
                unit: 'tablespoon',
                name: 'Green lentils',
                prepNote: 'finely chopped',
                showNote: true,
              ),
            ),
          );
          c.draft.steps.clear();
          c.draft.steps.addAll([
            EditableStep('Mix green lentils gently.'),
            EditableStep('Cook until soft.'),
          ]);
          Finder field(String part, int row) => find.byKey(
            ValueKey(
              part == 'step'
                  ? '${c.draft.steps[row].id}-text'
                  : '${rows[row].id}-$part',
            ),
          );
          Finder input(Finder f) =>
              find.descendant(of: f, matching: find.byType(EditableText));
          await tester.pumpWidget(
            MaterialApp(
              theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
              builder: (context, child) => Actions(
                actions: {
                  // Match CookdexApp, including touch tap-outside dismissal.
                  EditableTextTapOutsideIntent:
                      CallbackAction<EditableTextTapOutsideIntent>(
                        onInvoke: (intent) {
                          intent.focusNode.unfocus();
                          return null;
                        },
                      ),
                },
                child: child!,
              ),
              home: RecipeEditor(controller: c),
            ),
          );
          await tester.pumpAndSettle();
          final from = field(source, 0);
          // Different types cover within-row switching; same types cover rows.
          final to = field(target, source == target ? 1 : 0);
          await tester.ensureVisible(from);
          await tester.tap(from);
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.ensureVisible(to);
          await tester.pumpAndSettle();
          expect(input(to), findsNothing);
          for (var pass = 0; pass < 2; pass++) {
            if (pass == 1) {
              await tester.tap(from);
              await tester.pumpAndSettle();
            }
            final previous = tester.widget<EditableText>(input(from));
            tester.testTextInput.log.clear();
            final point = tester.getTopLeft(to) + const Offset(28, 22);
            final gesture = await tester.startGesture(point);
            await tester.pump();
            expect(
              previous.focusNode.hasFocus,
              isTrue,
              reason:
                  'Pointer down on another field is not an outside dismissal',
            );
            await gesture.up();
            await tester.pumpAndSettle();
            final next = tester.widget<EditableText>(input(to));
            expect(next.focusNode.hasFocus, isTrue);
            final render = tester
                .state<EditableTextState>(input(to))
                .renderEditable;
            expect(
              next.controller.selection,
              TextSelection.collapsed(
                offset: render.getPositionForPoint(point).offset,
              ),
            );
            expect(
              tester.testTextInput.log.where(
                (m) => m.method == 'TextInput.hide',
              ),
              isEmpty,
            );
            expect(tester.testTextInput.isVisible, isTrue);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
