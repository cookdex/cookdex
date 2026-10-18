import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor, reveal;

Finder rowField(String id, String part) => find.byKey(ValueKey('$id-$part'));

Finder inputIn(Finder outer) =>
    find.descendant(of: outer, matching: find.byType(EditableText));

Future<void> activate(WidgetTester tester, Finder outer) async {
  await reveal(tester, outer);
  await tester.tap(outer);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'scroll hides keyboard while retaining text, selection and native undo',
    (tester) async {
      final (c, _, _) = await controller();
      final rows = c.draft.sections.first.rows;
      final row = rows.first..name = 'Lentils';
      rows.addAll(
        List.generate(30, (i) => EditableIngredient(name: 'Ingredient $i')),
      );
      await editor(tester, c, size: const Size(412, 900));
      final name = rowField(row.id, 'name');
      await activate(tester, name);
      await tester.pump(const Duration(milliseconds: 600));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Red lentils',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final nativeBefore = tester.state<EditableTextState>(inputIn(name));
      final scroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final position = tester.state<ScrollableState>(scroll).position;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      tester.testTextInput.log.clear();
      position.jumpTo(position.pixels + 20);
      await tester.pump();
      expect(
        tester.testTextInput.log.where((m) => m.method == 'TextInput.hide'),
        isEmpty,
      );
      await tester.drag(scroll, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(
        tester.testTextInput.log.where((m) => m.method == 'TextInput.hide'),
        isNotEmpty,
      );
      // Model the platform's completed IME dismissal, then leave the row's cache.
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await tester.drag(scroll, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(nativeBefore.widget.focusNode.hasFocus, isTrue);
      await reveal(tester, name);
      expect(
        tester.state<EditableTextState>(inputIn(name)),
        same(nativeBefore),
      );
      expect(
        nativeBefore.widget.controller.value,
        const TextEditingValue(
          text: 'Red lentils',
          selection: TextSelection.collapsed(offset: 4),
        ),
      );
      tester
          .state<UndoHistoryState<TextEditingValue>>(
            find.descendant(
              of: name,
              matching: find.byType(UndoHistory<TextEditingValue>),
            ),
          )
          .undo();
      await tester.pump();
      expect(row.name, 'Lentils');
    },
  );

  for (final heldSecondPress in [false, true]) {
    final scenario = heldSecondPress ? 'held second press' : 'second drag';
    testWidgets('activation replay matches native behavior for $scenario', (
      tester,
    ) async {
      const originalText = 'Green lentils and carrots';
      Future<({TextSelection during, TextSelection after, bool handles})>
      exercise({required bool preactivated}) async {
        await tester.pumpWidget(const SizedBox.shrink());
        final (c, _, _) = await controller();
        final row = c.draft.sections.first.rows.first..name = originalText;
        await editor(tester, c, size: const Size(900, 844));
        final outer = rowField(row.id, 'name');
        await reveal(tester, outer);
        if (preactivated) {
          // Use the identical real field as a native control, after all prior
          // tap-replay/double-tap windows have expired.
          await activate(tester, outer);
          await tester.pump(const Duration(seconds: 1));
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
        } else {
          expect(inputIn(outer), findsNothing);
        }
        final start = tester.getTopLeft(outer) + const Offset(36, 22);
        await tester.tapAt(start);
        await tester.pump(const Duration(milliseconds: 100));
        final render = tester
            .state<EditableTextState>(inputIn(outer))
            .renderEditable;
        final end = render.localToGlobal(
          render.getLocalRectForCaret(const TextPosition(offset: 11)).center,
        );
        expect((end - start).distance, greaterThan(40));
        final second = await tester.startGesture(start + const Offset(1, 0));
        if (heldSecondPress) {
          await tester.pump(const Duration(milliseconds: 600));
        }
        for (var i = 1; i <= 6; i++) {
          await second.moveTo(Offset.lerp(start, end, i / 6)!);
          await tester.pump(const Duration(milliseconds: 30));
        }
        final during = tester
            .widget<EditableText>(inputIn(outer))
            .controller
            .selection;
        await second.up();
        await tester.pumpAndSettle();
        final input = tester.widget<EditableText>(inputIn(outer));
        expect(input.controller.text, originalText);
        expect(row.name, originalText);
        return (
          during: during,
          after: input.controller.selection,
          handles: input.showSelectionHandles,
        );
      }

      final native = await exercise(preactivated: true);
      final activated = await exercise(preactivated: false);
      expect(activated.during, native.during);
      expect(
        activated.after,
        native.after,
        reason:
            'Releasing the second pointer must not replay a double tap '
            'over the native drag or held-press selection.',
      );
      expect(activated.handles, native.handles);
    });
  }
  for (final gesture in ['long press', 'double tap']) {
    testWidgets('first $gesture selects the native word from an idle row', (
      tester,
    ) async {
      final (c, _, _) = await controller();
      final row = c.draft.sections.first.rows.first..name = 'Green lentils';
      await editor(tester, c);
      final outer = rowField(row.id, 'name');
      await reveal(tester, outer);
      expect(inputIn(outer), findsNothing);
      final point = tester.getTopLeft(outer) + const Offset(36, 22);
      if (gesture == 'long press') {
        await tester.longPressAt(point);
      } else {
        await tester.tapAt(point);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(point);
      }
      await tester.pumpAndSettle();
      final input = tester.widget<EditableText>(inputIn(outer));
      expect(
        input.controller.selection.textInside(input.controller.text),
        'Green',
      );
      expect(input.showSelectionHandles, isTrue);
    });
  }
  testWidgets(
    'first long press continues selecting while the same pointer drags',
    (tester) async {
      final (c, _, _) = await controller();
      const originalText = 'Green lentils and carrots';
      final row = c.draft.sections.first.rows.first..name = originalText;
      // Keep all words on one line so this measures pointer handoff rather than
      // autoscroll or line-wrap selection behavior.
      await editor(tester, c, size: const Size(900, 844));
      final outer = rowField(row.id, 'name');
      await reveal(tester, outer);
      expect(inputIn(outer), findsNothing);
      final start = tester.getTopLeft(outer) + const Offset(36, 22);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      final initial = tester.widget<EditableText>(inputIn(outer));
      final initialSelection = initial.controller.selection;
      expect(initialSelection.textInside(originalText), 'Green');
      final render = tester
          .state<EditableTextState>(inputIn(outer))
          .renderEditable;
      final end = render.localToGlobal(
        render.getLocalRectForCaret(const TextPosition(offset: 11)).center,
      );
      // Never lift and restart: the idle row must hand this ongoing selection
      // gesture to the native field, including all subsequent pointer movement.
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(Offset.lerp(start, end, i / 6)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      final dragging = tester.widget<EditableText>(inputIn(outer));
      final expanded = dragging.controller.selection;
      expect(expanded.start, initialSelection.start);
      expect(expanded.end, greaterThan(initialSelection.end));
      expect(expanded.textInside(originalText), startsWith('Green '));
      expect(dragging.controller.text, originalText);
      await gesture.up();
      await tester.pumpAndSettle();
      final released = tester.widget<EditableText>(inputIn(outer));
      expect(released.controller.selection, expanded);
      expect(released.showSelectionHandles, isTrue);
      expect(released.controller.text, originalText);
      expect(row.name, originalText);
    },
  );
  testWidgets('first tap in an existing ingredient places caret at the tap', (
    tester,
  ) async {
    final (c, _, _) = await controller();
    final row = c.draft.sections.first.rows.first..name = 'Green lentils';
    await editor(tester, c);
    final outer = rowField(row.id, 'name');
    await reveal(tester, outer);
    // Tap inside the first word without first activating the field. This also
    // exercises a resting lightweight row when fields are mounted on demand.
    final point = tester.getTopLeft(outer) + const Offset(36, 22);
    await tester.tapAt(point);
    await tester.pumpAndSettle();
    final input = tester.widget<EditableText>(inputIn(outer));
    final render = tester
        .state<EditableTextState>(inputIn(outer))
        .renderEditable;
    final expected = render.getPositionForPoint(point).offset;
    expect(expected, inInclusiveRange(1, row.name.length - 1));
    expect(input.focusNode.hasFocus, isTrue);
    expect(input.controller.selection.isCollapsed, isTrue);
    expect(input.controller.selection.baseOffset, expected);
  });

  testWidgets(
    'keyboard Next activates unit then ingredient without losing amount',
    (tester) async {
      final (c, _, _) = await controller();
      final row = c.draft.sections.first.rows.first;
      await editor(tester, c);
      final amount = rowField(row.id, 'amount');
      await activate(tester, amount);
      tester.testTextInput.enterText('1/3');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(inputIn(rowField(row.id, 'unit')))
            .focusNode
            .hasFocus,
        isTrue,
      );
      tester.testTextInput.enterText('cup');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(inputIn(rowField(row.id, 'name')))
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(row.amount, '1/3');
      expect(row.unit, 'cup');
    },
  );

  testWidgets(
    'native text undo history survives leaving and returning to a row',
    (tester) async {
      final (c, _, _) = await controller();
      final row = c.draft.sections.first.rows.first..name = 'Lentils';
      await editor(tester, c);
      final name = rowField(row.id, 'name');
      await activate(tester, name);
      await tester.pump(const Duration(milliseconds: 600));
      tester.testTextInput.enterText('Red lentils');
      await tester.pump(const Duration(milliseconds: 600));
      await activate(tester, rowField(row.id, 'amount'));
      tester.testTextInput.enterText('2');
      await tester.pump(const Duration(milliseconds: 600));
      await activate(tester, name);
      tester
          .state<UndoHistoryState<TextEditingValue>>(
            find.descendant(
              of: name,
              matching: find.byType(UndoHistory<TextEditingValue>),
            ),
          )
          .undo();
      await tester.pump();
      expect(row.name, 'Lentils');
      expect(row.amount, '2');
      expect(
        tester.widget<EditableText>(inputIn(name)).controller.text,
        'Lentils',
      );
    },
  );

  testWidgets('reordering retains the focused row content and persisted edits', (
    tester,
  ) async {
    final storage = MemoryDraftStorage();
    final (c, _, _) = await controller(storage: storage);
    final rows = c.draft.sections.first.rows;
    final first = rows.first..name = 'Lentils';
    final second = EditableIngredient(name: 'Carrots');
    rows.add(second);
    await editor(tester, c, size: const Size(900, 1400));
    final name = rowField(first.id, 'name');
    await activate(tester, name);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'Red lentils',
        selection: TextSelection.collapsed(offset: 4),
      ),
    );
    await tester.pump();
    // Gesture and accessible reorder dispatch already have separate coverage;
    // this checks keyed field state through the actual controller notification.
    c.reorder(rows, 0, 1);
    await tester.pumpAndSettle();
    final input = tester.widget<EditableText>(inputIn(name));
    expect(rows.map((row) => row.id), [second.id, first.id]);
    expect(input.controller.text, 'Red lentils');
    await c.flush();
    final savedRows =
        ((await storage.read())!['sections'] as List).first['rows'] as List;
    expect(savedRows.last['id'], first.id);
    expect(savedRows.last['name'], 'Red lentils');
    expect(savedRows.first['name'], 'Carrots');
  });
}
