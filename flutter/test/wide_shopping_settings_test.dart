import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/staples_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_recipe_controls_test.dart' show shoppingControlStore;
import 'shopping_screen_test.dart' show item, setup, menu;

SettingsScreen wideSettingsFixture({ScrollController? controller}) =>
    SettingsScreen(
      controller: controller,
      readHasPrevious: () => false,
      syncSummary: 'Not paired',
      shoppingKeepAwake: false,
      onShoppingKeepAwake: (_) {},
      recipeTextScale: 1,
      onRecipeTextScale: (_) {},
      isAndroid: true,
      wallpaperColors: false,
      onWallpaperColors: (_) {},
      version: '1.10.5+20005',
    );

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1280, 800),
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme().copyWith(platform: platform),
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollMargins(WidgetTester tester, Finder scroll) async {
  final position = tester.state<ScrollableState>(scroll).position;
  final rect = tester.getRect(scroll);
  expect(rect.width, 1280);
  expect(position.maxScrollExtent, greaterThan(300));
  for (final x in [rect.left + 24, rect.right - 24]) {
    final start = Offset(x, rect.center.dy);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.dragFrom(start, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: 'Touch drag at x=$x');
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: start,
        scrollDelta: const Offset(0, 140),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: 'Mouse wheel at x=$x');
  }
  expect(tester.takeException(), isNull);
}

Finder _verticalScroll(Finder parent) => find
    .descendant(
      of: parent,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    )
    .first;

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'Shopping scrolls from both blank margins on ${platform.name}',
      (tester) async {
        final (store, repository) = await setup([
          for (var i = 0; i < 40; i++)
            item('food-$i', 'Food $i', category: 'produce'),
        ]);
        await _mount(
          tester,
          ShoppingScreen(store: store, onSaveText: (_) async {}),
          platform: platform,
        );
        await _scrollMargins(
          tester,
          _verticalScroll(find.byType(ShoppingScreen)),
        );
        expect(repository.edits, 0);
      },
    );

    testWidgets(
      'Settings scrolls from both blank margins on ${platform.name}',
      (tester) async {
        await _mount(tester, wideSettingsFixture(), platform: platform);
        await _scrollMargins(
          tester,
          _verticalScroll(find.byType(SettingsScreen)),
        );
      },
    );

    testWidgets('Staples scrolls from both blank margins on ${platform.name}', (
      tester,
    ) async {
      final (store, _) = await setup([]);
      store.preferences.setStaples([for (var i = 0; i < 35; i++) 'staple $i']);
      await _mount(tester, StaplesScreen(store: store), platform: platform);
      await _scrollMargins(tester, _verticalScroll(find.byType(StaplesScreen)));
    });

    testWidgets(
      'Removal preview scrolls from both blank margins on ${platform.name}',
      (tester) async {
        final (store, repository) = await shoppingControlStore();
        for (var i = 0; i < 25; i++) {
          repository.items.add(
            item('extra-$i', 'Ingredient $i', sources: ['bowl']),
          );
          repository.lines.add(
            ShoppingRemovalLine(
              id: 'extra-$i',
              name: 'Ingredient $i',
              before: '1 cup',
              after: null,
              action: 'remove',
              reason: '',
            ),
          );
        }
        await store.refresh();
        await _mount(
          tester,
          ShoppingScreen(store: store, onSaveText: (_) async {}),
          platform: platform,
        );
        await menu(tester, 'Recipes on this list');
        await tester.tap(find.byKey(const ValueKey('shopping-recipe-bowl')));
        await tester.pumpAndSettle();
        await _scrollMargins(
          tester,
          _verticalScroll(find.byKey(const Key('shopping-removal-scroll'))),
        );
        expect(repository.removalCalls, 0);
      },
    );
  }

  for (final (size, platform, expected) in [
    (const Size(1280, 800), TargetPlatform.android, 850.0),
    (const Size(1600, 1000), TargetPlatform.windows, 850.0),
    (const Size(1000, 1280), TargetPlatform.android, 968.0),
    (const Size(390, 844), TargetPlatform.android, 358.0),
  ]) {
    testWidgets(
      'Shopping heading, list and Add item align at $size ${platform.name}',
      (tester) async {
        final (store, _) = await setup([
          item('first', 'First item', category: 'produce'),
        ]);
        await _mount(
          tester,
          ShoppingScreen(store: store, onSaveText: (_) async {}),
          size: size,
          platform: platform,
        );
        final itemBounds = tester.getRect(find.byKey(const ValueKey('first')));
        final titleBounds = tester.getRect(find.text('Shopping list'));
        final input = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Add an item',
        );
        final inputBounds = tester.getRect(input);
        final addBounds = tester.getRect(find.byTooltip('Add item'));
        expect(itemBounds.width, expected);
        expect(titleBounds.left, itemBounds.left);
        expect(inputBounds.left, itemBounds.left);
        expect(addBounds.right, itemBounds.right);
        expect(
          tester.getRect(find.byTooltip('Shopping list options')).right,
          itemBounds.right + 8,
        );
      },
    );

    testWidgets(
      'Settings cards retain the reading width at $size ${platform.name}',
      (tester) async {
        await _mount(
          tester,
          wideSettingsFixture(),
          size: size,
          platform: platform,
        );
        final cardBounds = tester.getRect(find.byType(Card).first);
        expect(cardBounds.width, expected);
        expect(tester.getRect(find.text('Settings')).left, cardBounds.left);
      },
    );
  }

  for (final upward in [false, true]) {
    testWidgets(
      'wide Shopping preserves held cross-category ${upward ? 'upward' : 'downward'} drag',
      (tester) async {
        final (store, repository) = await setup([
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
        await _mount(
          tester,
          ShoppingScreen(store: store, onSaveText: (_) async {}),
        );
        final sourceId = upward ? 'b' : 'a';
        final source = find.descendant(
          of: find.byKey(ValueKey(sourceId)),
          matching: find.byType(ReorderableDelayedDragStartListener),
        );
        final start = tester.getCenter(source);
        final destination = upward
            ? tester.getTopLeft(find.byKey(const ValueKey('a'))).dy + 5
            : tester.getCenter(find.byKey(const ValueKey('b'))).dy - 10;
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
        expect(repository.edits, 1);
        final edit = repository.lastEdit as ShoppingEdit_Move;
        expect(edit.id, sourceId);
        expect(edit.categoryId, upward ? 'produce' : 'pantry');
        expect(edit.beforeId, upward ? 'a' : 'c');
        expect(
          store.shopping
              .where((row) => row.categoryId == edit.categoryId && !row.checked)
              .map((row) => row.id),
          upward ? ['b', 'a'] : ['b', 'a', 'c'],
        );
        expect(
          store.shopping.singleWhere((row) => row.id == 'checked').checked,
          isTrue,
        );
        expect(
          store.shopping.singleWhere((row) => row.id == 'a').quantityText,
          '2–3',
        );
        expect(
          store.shopping.singleWhere((row) => row.id == 'a').contributorIds,
          ['a'],
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
