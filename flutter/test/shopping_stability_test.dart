import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cookdex/src/rust/api.dart';

import 'shopping_screen_test.dart' show setup, item, screen, input;

void main() {
  testWidgets('bulk checks finish for offscreen rows as well as visible rows', (
    tester,
  ) async {
    final (store, _) = await setup([
      for (var i = 0; i < 40; i++) item('$i', 'Item $i'),
    ]);
    await screen(tester, store);
    await store.editShopping(
      ShoppingEdit.check(
        ids: [for (var i = 0; i < 40; i++) '$i'],
        checked: true,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('Checked (40)'), findsOneWidget);
    expect(find.text('Item 0'), findsNothing);
    await tester.tap(find.text('Checked (40)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Item 39'));
    await tester.pumpAndSettle();
    expect(find.text('Item 39').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending write and committed check do not shift the list viewport',
    (tester) async {
      final (store, repo) = await setup([
        item('a', 'Carrots'),
        item('b', 'Flour'),
        item('c', 'Rice'),
      ]);
      await screen(tester, store);
      final before = tester.getTopLeft(find.text('Flour'));
      final inputBefore = tester.getTopLeft(input());
      repo.gate = Completer<void>();
      await tester.tap(find.text('Carrots'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getTopLeft(find.text('Flour')),
        before,
        reason: 'A pending database write must not insert layout space.',
      );
      expect(tester.getTopLeft(input()), inputBefore);
      repo.gate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.text('Flour')),
        before,
        reason: 'The durable snapshot changes the checkbox, not list geometry.',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(find.text('Flour'));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.getTopLeft(find.text('Flour')), settled);
      expect(tester.getTopLeft(input()), inputBefore);
    },
  );

  testWidgets('removal waits for the rendered collapse to reach zero height', (
    tester,
  ) async {
    final (store, _) = await setup([item('a', 'Carrots'), item('b', 'Flour')]);
    await screen(tester, store);
    await tester.tap(find.text('Carrots'));
    await tester.pump();
    // Deliberately delay the first rendered animation frame, as a real device can.
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 160));
    expect(
      find.byKey(const ValueKey('shopping-row-a-false')),
      findsOneWidget,
      reason: 'A wall-clock timer must not remove a partially collapsed row.',
    );
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(find.text('Checked (1)'), findsOneWidget);
    expect(find.text('Carrots'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
