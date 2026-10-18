import 'package:cookdex/src/rust/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_screen_test.dart' show item, setup, screen, menu;

void main() {
  for (final scenario in ['downward', 'upward', 'append']) {
    testWidgets('held cross-category drag $scenario inserts at drop position', (
      tester,
    ) async {
      final (store, repo) = await setup([
        item(
          'a',
          'Apples',
          category: 'produce',
          quantity: '2–3',
          sources: ['a'],
        ),
        item('b', 'Beans', category: 'pantry'),
        item('c', 'Couscous', category: 'pantry'),
        item('d', 'Dish soap'),
        item('checked', 'Checked rice', checked: true, category: 'pantry'),
      ]);
      await screen(tester, store);
      final sourceId = scenario == 'upward' ? 'b' : 'a';
      final source = find.descendant(
        of: find.byKey(ValueKey(sourceId)),
        matching: find.byType(ReorderableDelayedDragStartListener),
      );
      final destination = scenario == 'upward'
          ? tester.getTopLeft(find.byKey(const ValueKey('a'))).dy + 5
          : scenario == 'append'
          ? tester.getCenter(find.byKey(const ValueKey('c'))).dy - 10
          : tester.getCenter(find.byKey(const ValueKey('b'))).dy - 10;
      final start = tester.getCenter(source);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      for (var i = 1; i <= 15; i++) {
        await gesture.moveTo(
          Offset(start.dx, start.dy + (destination - start.dy) * i / 15),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(repo.lastEdit, isA<ShoppingEdit_Move>());
      final edit = repo.lastEdit as ShoppingEdit_Move;
      expect(edit.id, sourceId);
      expect(edit.categoryId, scenario == 'upward' ? 'produce' : 'pantry');
      expect(
        edit.beforeId,
        scenario == 'upward'
            ? 'a'
            : scenario == 'append'
            ? null
            : 'c',
      );
      final moved = store.shopping.singleWhere((row) => row.id == sourceId);
      expect(moved.checked, false);
      if (sourceId == 'a') {
        expect(moved.quantityText, '2–3');
        expect(moved.contributorIds, ['a']);
      }
      expect(
        store.shopping.singleWhere((row) => row.id == 'checked').checked,
        true,
      );
      expect(
        store.shopping
            .where((row) => row.categoryId == edit.categoryId && !row.checked)
            .map((row) => row.id),
        scenario == 'upward'
            ? ['b', 'a']
            : scenario == 'append'
            ? ['b', 'c', 'a']
            : ['b', 'a', 'c'],
      );
      expect(find.text('Move to category'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('swiping across an item handle scrolls without reorder or menu', (
    tester,
  ) async {
    final (store, repo) = await setup(
      List.generate(30, (i) => item('i$i', 'Item $i', category: 'produce')),
    );
    await screen(tester, store);
    final first = find.byType(ReorderableDelayedDragStartListener).at(4);
    final gesture = await tester.startGesture(tester.getCenter(first));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -15));
      await tester.pump(const Duration(milliseconds: 10));
    }
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repo.edits, 0);
    expect(find.text('Move to category'), findsNothing);
    expect(
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels,
      greaterThan(0),
    );
  });

  testWidgets(
    'category movement preserves sources and checked rows return to their category',
    (tester) async {
      final (store, _) = await setup([
        item(
          'carrot',
          'Carrots',
          category: 'produce',
          quantity: '2–3',
          sources: ['a'],
        ),
        item('flour', 'Flour', category: 'pantry'),
        item('salt', 'Salt', checked: true, category: 'pantry'),
      ]);
      await screen(tester, store);
      expect(find.text('Other'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Produce').first).dy,
        lessThan(tester.getTopLeft(find.text('Pantry').first).dy),
      );
      await tester.longPress(find.text('2–3 Carrots'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move to category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      final moved = store.shopping.singleWhere((row) => row.id == 'carrot');
      expect(moved.categoryId, 'other');
      expect(moved.contributorIds, ['a']);
      expect(find.text('Produce'), findsNothing);
      await tester.tap(find.text('Checked (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salt'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Checked (1)'), findsNothing);
      expect(
        tester.getTopLeft(find.text('Salt')).dy,
        lessThan(tester.getTopLeft(find.text('Other').first).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('category add rename delete and protected fallback', (
    tester,
  ) async {
    final (store, repo) = await setup([
      item('carrot', 'Carrots', category: 'produce'),
    ]);
    await screen(tester, store);
    await menu(tester, 'Categories');
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a category name.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Frozen');
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(store.shoppingCategories.last.name, 'Frozen');
    await tester.tap(find.text('Produce'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Fruit and vegetables');
    repo.fail = true;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Write failed.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Fruit and vegetables',
    );
    repo.fail = false;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fruit and vegetables options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('remembered ingredient choices'),
      findsOneWidget,
    );
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(store.shopping.single.categoryId, 'other');
    expect(store.shoppingCategories.any((c) => c.id == 'produce'), false);
    await tester.tap(find.byTooltip('Other options'));
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    await tester.tapAt(const Offset(10, 100));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'held handles reorder unchecked rows and categories without checking',
    (tester) async {
      final (store, repo) = await setup([
        item('a', 'Apples', category: 'produce'),
        item('b', 'Bananas', category: 'produce'),
        item('c', 'Carrots', checked: true, category: 'produce'),
      ]);
      await screen(tester, store);
      final handles = find.byType(ReorderableDelayedDragStartListener);
      expect(handles, findsNWidgets(2));
      final handle = handles.last;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Move to category'), findsNothing);
      await gesture.moveBy(const Offset(0, -1));
      expect(find.text('Move to category'), findsNothing);
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(repo.lastEdit, isA<ShoppingEdit_ReorderItems>());
      expect((repo.lastEdit as ShoppingEdit_ReorderItems).ids, ['b', 'a']);
      expect(store.shopping.where((i) => !i.checked).map((i) => i.id), [
        'b',
        'a',
      ]);
      expect(store.shopping.last.checked, true);
      await tester.tap(find.text('Checked (1)'));
      await tester.pumpAndSettle();
      expect(handles, findsNWidgets(2));
      await menu(tester, 'Categories');
      final categoryDrag = await tester.startGesture(
        tester.getCenter(handles.at(1)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await categoryDrag.moveBy(const Offset(0, -1));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await categoryDrag.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await categoryDrag.up();
      await tester.pumpAndSettle();
      expect(repo.lastEdit, isA<ShoppingEdit_ReorderCategories>());
      expect(store.shoppingCategories.map((c) => c.id), [
        'pantry',
        'produce',
        'other',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
