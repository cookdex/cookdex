import 'package:cookdex/src/rust/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_screen_test.dart' show item, setup, screen;

Finder band(String category) =>
    find.byKey(ValueKey('pinned-shopping-$category'));

void main() {
  for (final upward in [false, true]) {
    testWidgets(
      'held cross-category ${upward ? 'upward' : 'downward'} drag with pinned band preserves model order',
      (tester) async {
        final (store, repo) = await setup([
          for (var i = 0; i < 8; i++)
            item(
              'p$i',
              'Produce item $i',
              category: 'produce',
              quantity: '2–3',
              sources: ['a'],
            ),
          item('b', 'Beans', category: 'pantry'),
          item('c', 'Couscous', category: 'pantry'),
          item('d', 'Dates', category: 'pantry'),
          for (var i = 0; i < 12; i++) item('o$i', 'Other item $i'),
          item('checked', 'Checked rice', category: 'pantry', checked: true),
        ]);
        await screen(tester, store, size: const Size(320, 800));
        final scrollable = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(250);
        await tester.pumpAndSettle();
        final viewportTop = tester.getTopLeft(scrollable).dy;
        final pinned = tester.renderObject<RenderSliver>(band('produce'));
        expect(
          (pinned.parentData! as SliverPhysicalParentData).paintOffset.dy,
          0,
        );
        // A band tap must not check the row it visually covers.
        await tester.tapAt(Offset(30, viewportTop + 20));
        await tester.pumpAndSettle();
        expect(repo.edits, 0);

        final sourceId = upward ? 'b' : 'p6';
        final source = find.descendant(
          of: find.byKey(ValueKey(sourceId)),
          matching: find.byType(ReorderableDelayedDragStartListener),
        );
        final destination = upward
            ? tester.getTopLeft(find.byKey(const ValueKey('p5'))).dy + 5
            : tester.getCenter(find.byKey(const ValueKey('b'))).dy - 10;
        final start = tester.getCenter(source);
        expect(start.dy, greaterThan(viewportTop + 40));
        expect(destination, greaterThan(viewportTop + 40));
        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 600));
        for (var step = 1; step <= 15; step++) {
          await gesture.moveTo(
            Offset(start.dx, start.dy + (destination - start.dy) * step / 15),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.pump(const Duration(milliseconds: 300));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(repo.edits, 1);
        final edit = repo.lastEdit as ShoppingEdit_Move;
        expect(edit.id, sourceId);
        expect(edit.categoryId, upward ? 'produce' : 'pantry');
        expect(edit.beforeId, upward ? 'p5' : 'c');
        final expected = upward
            ? ['p0', 'p1', 'p2', 'p3', 'p4', 'b', 'p5', 'p6', 'p7']
            : ['b', 'p6', 'c', 'd'];
        for (final rows in [store.shopping, repo.items]) {
          expect(
            rows
                .where(
                  (row) => row.categoryId == edit.categoryId && !row.checked,
                )
                .map((row) => row.id),
            expected,
          );
          expect(rows.where((row) => row.checked).map((row) => row.id), [
            'checked',
          ]);
          final retained = rows.singleWhere((row) => row.id == 'p6');
          expect(retained.quantityText, '2–3');
          expect(retained.contributorIds, ['a']);
        }
        final produceCount = find.descendant(
          of: band('produce'),
          matching: find.text(upward ? '9' : '7'),
        );
        final pantryCount = find.descendant(
          of: band('pantry'),
          matching: find.text(upward ? '2' : '4'),
        );
        expect(produceCount, findsOneWidget);
        expect(pantryCount, findsOneWidget);
        expect(find.text('Move to category'), findsNothing);
        expect(find.text('Edit item'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('category pins, yields to next aisle and never covers Checked', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final (store, _) = await setup([
      for (var i = 0; i < 20; i++)
        item('p$i', 'Produce item $i', category: 'produce'),
      for (var i = 0; i < 20; i++) item('o$i', 'Other item $i'),
      for (var i = 0; i < 20; i++)
        item('c$i', 'Checked item $i', checked: true),
    ]);
    await screen(tester, store, size: const Size(320, 640));
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final header = tester.renderObject<RenderSliver>(band('produce'));
    expect(header.geometry!.scrollExtent, 40);
    position.jumpTo(300);
    await tester.pump();
    expect((header.parentData! as SliverPhysicalParentData).paintOffset.dy, 0);
    expect(find.bySemanticsLabel('Produce, 20 unchecked'), findsOneWidget);

    // Use the actual second heading's position, independent of row heights.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shopping-row-o0-false')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final viewportTop = tester.getTopLeft(find.byType(Scrollable).first).dy;
    final headingTop =
        tester
            .getTopLeft(find.byKey(const ValueKey('shopping-row-o0-false')))
            .dy -
        40;
    position.jumpTo(position.pixels + headingTop - viewportTop - 20);
    await tester.pump();
    expect(
      (header.parentData! as SliverPhysicalParentData).paintOffset.dy,
      -20,
    );
    position.jumpTo(position.pixels + 30);
    await tester.pump();
    final labels = <int>[];
    void inspect(SemanticsNode node) {
      if (node.label == 'Other, 20 unchecked') labels.add(node.id);
      node.visitChildren((child) {
        inspect(child);
        return true;
      });
    }

    inspect(
      tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    expect(labels, hasLength(1));

    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Checked (20)'));
    await tester.tap(find.text('Checked (20)'));
    await tester.pumpAndSettle();
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    labels.clear();
    inspect(
      tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    expect(labels, isEmpty);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp large text wraps full category name and keeps count', (
    tester,
  ) async {
    final (store, _) = await setup([
      item('p', 'Carrots', category: 'produce'),
      item('q', 'Beans', category: 'produce'),
    ]);
    await store.editShopping(
      const ShoppingEdit.renameCategory(
        id: 'produce',
        name: 'Fresh vegetables and fruit for the week',
      ),
    );
    await screen(tester, store, size: const Size(320, 640), scale: 2);
    final header = find.byKey(const ValueKey('shopping-heading-produce')).first;
    expect(tester.getSize(header).width, 320);
    expect(
      find.descendant(of: header, matching: find.text('2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await store.editShopping(
      const ShoppingEdit.check(ids: ['p'], checked: true),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: header, matching: find.text('1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
