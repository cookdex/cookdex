import 'package:cookdex/editor_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, editor, reveal, enterFieldText;

void main() {
  testWidgets('held ingredient handle drags past an empty section label', (
    tester,
  ) async {
    final (c, _, _) = await controller();
    final row = EditableIngredient(name: 'onion', amount: '2', unit: 'tbsp');
    final top = EditableSection(rows: [row]);
    final sauce = EditableSection(name: 'Sauce');
    c.draft.sections
      ..clear()
      ..addAll([top, sauce]);
    c.changed();
    await editor(tester, c, size: const Size(600, 1600));
    final handle = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Reorder ingredient 1',
    );
    final pointer = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 600));
    final destination = tester.getCenter(
      find.byKey(ValueKey('${sauce.id}-actions')),
    );
    await pointer.moveTo(destination + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 350));
    await pointer.up();
    await tester.pumpAndSettle();
    expect(top.rows, isEmpty);
    expect(sauce.rows.single, same(row));
    expect(row.amount, '2');
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'cross-section drop preserves edited fields through recycling and save',
    (tester) async {
      final (c, repo, _) = await controller();
      final moved = EditableIngredient(
        name: 'original',
        amount: '1/3',
        unit: 'cup',
        prepNote: 'finely chopped',
        optional: true,
      );
      final top = EditableSection(rows: [moved]);
      final sauce = EditableSection(
        name: 'Sauce',
        rows: [EditableIngredient(name: 'tomato')],
      );
      final empty = EditableSection(name: 'Topping');
      c.draft.title = 'Cross-section soup';
      c.draft.sections
        ..clear()
        ..addAll([top, sauce, empty]);
      c.draft.steps
        ..clear()
        ..addAll(List.generate(30, (i) => EditableStep('Step $i')));
      c.changed();
      await editor(tester, c);
      final name = find.byKey(ValueKey('${moved.id}-name'));
      await reveal(tester, name);
      await enterFieldText(tester, name, 'fresh onion');
      await tester.ensureVisible(find.byKey(ValueKey('${moved.id}-amount')));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byWidgetPredicate((w) => w is CustomScrollView).first,
        const Offset(0, 160),
      );
      await tester.pumpAndSettle();
      await enterFieldText(
        tester,
        find.byKey(ValueKey('${moved.id}-amount')),
        '1/2–3/4',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      void drop(int from, int to) {
        tester
            .widget<SliverReorderableList>(
              find.byType(SliverReorderableList).first,
            )
            .onReorderItem!(from, to);
      }

      // [top header, moved, actions, Sauce, tomato, actions, Topping, actions]
      drop(1, 4); // after tomato, before Sauce actions
      await tester.pumpAndSettle();
      expect(sauce.rows, [sauce.rows.first, moved]);
      expect(top.rows, isEmpty);
      // [top header, actions, Sauce, tomato, moved, actions, Topping, actions]
      drop(4, 6); // after empty Topping label
      await tester.pumpAndSettle();
      expect(empty.rows.single, same(moved));
      drop(6, 1); // back into unnamed top group
      await tester.pumpAndSettle();
      expect(top.rows.single, same(moved));
      drop(1, 3); // first ingredient after Sauce label
      await tester.pumpAndSettle();
      expect(sauce.rows.first, same(moved));
      await reveal(tester, find.byKey(const ValueKey('notes')));
      expect(name, findsNothing);
      final scrollable = find.byType(Scrollable).first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pumpAndSettle();
      await reveal(tester, name);
      await enterFieldText(tester, name, '${moved.name} diced');
      expect(moved.name, 'fresh onion diced');
      expect(moved.amount, '1/2–3/4');
      expect(moved.unit, 'cup');
      expect(moved.prepNote, 'finely chopped');
      expect(moved.optional, isTrue);
      final saved = await c.save();
      expect(saved, isNotNull);
      final ingredients = repo.recipes.values.single.fields.ingredients;
      expect(ingredients.map((i) => i.name), ['fresh onion diced', 'tomato']);
      expect(ingredients.map((i) => i.section), ['Sauce', 'Sauce']);
      expect(repo.inputs, ['1/2–3/4', '']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
