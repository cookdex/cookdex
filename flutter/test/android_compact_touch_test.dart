import 'package:cookdex/ui/compact_touch_target.dart';
import 'package:flutter/rendering.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/recipe_favorite_button.dart';

import 'dart:ui' as ui;

import 'package:cookdex/ui/pixel_scroll.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

class _Fixture {
  final controller = PixelScrollController();
  final preferences = LocalPreferences.memory()..view = RecipeView.compact;
  late final RecipeStore store = RecipeStore(
    FakeRepository([
      for (var i = 0; i < 500; i++) recipe('$i', title: 'Garden soup $i'),
    ]),
    preferences,
  );
  final opened = <String>[],
      actions = <String>[],
      selectionToggles = <String>[];
  final selecting = ValueNotifier(false);
  final theme = ValueNotifier(cookdexTheme());
}

Finder touchRows() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('compact-row-'),
);
Finder touchStars() => find.byWidgetPredicate(
  (w) =>
      w.key is ValueKey<String> &&
      (w.key! as ValueKey<String>).value.startsWith('compact-star-'),
);

Future<_Fixture> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  final f = _Fixture();
  await f.store.initialize();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    f.controller.dispose();
    f.preferences.dispose();
    f.store.dispose();
    f.selecting.dispose();
    f.theme.dispose();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    debugDefaultTargetPlatformOverride = null;
  });
  await tester.pumpWidget(
    ValueListenableBuilder(
      valueListenable: f.theme,
      builder: (context, theme, _) => MaterialApp(
        theme: theme,
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
          body: ValueListenableBuilder(
            valueListenable: f.selecting,
            builder: (context, selecting, _) => RecipesScreen(
              store: f.store,
              preferences: f.preferences,
              controller: f.controller,
              selectedIds: selecting ? <String>{} : null,
              onToggleSelection: f.selectionToggles.add,
              onOpenRecipe: f.opened.add,
              onActions: (recipe) => f.actions.add(recipe.id),
              onAdd: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return f;
}

Future<void> _coast(
  WidgetTester tester,
  _Fixture f, {
  double start = 5000,
}) async {
  f.controller.jumpTo(start);
  await tester.pumpAndSettle();
  await tester.fling(
    find.byKey(const PageStorageKey('recipes-scroll')),
    const Offset(0, -600),
    5200,
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 8));
  }
  expect(f.controller.position.isScrollingNotifier.value, isTrue);
}

Finder visible(WidgetTester tester, Finder candidates) {
  for (final e in candidates.evaluate()) {
    final finder = find.byWidget(e.widget);
    final rect = tester.getRect(finder);
    if (rect.top > 200 && rect.bottom < 750) return finder;
  }
  throw StateError('Expected a visible Compact row');
}

String idOf(WidgetTester tester, Finder finder, String prefix) =>
    (tester.widget(finder).key! as ValueKey<String>).value.substring(
      prefix.length,
    );

void main() {
  for (final view in [RecipeView.compact, RecipeView.cards]) {
    for (final wide in [false, true]) {
      testWidgets(
        'Touch ${view.name} holds show feedback, with no idle feedback (wide=$wide)',
        (tester) async {
          final f = await _mount(tester);
          f.preferences.setView(view);
          if (wide) tester.view.physicalSize = const Size(1024, 768);
          await tester.pumpAndSettle();
          final prefix = view == RecipeView.compact ? 'compact' : 'card';
          final rows = find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('$prefix-row-'),
          );
          final row = visible(tester, rows);
          final id = idOf(tester, row, '$prefix-row-');
          final feedback = find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_PressInk',
          );
          expect(feedback, findsNothing);
          final point = tester.getRect(row).centerLeft + const Offset(35, 0);
          final press = await tester.startGesture(point);
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(feedback, findsOneWidget);
          await tester.pump(const Duration(milliseconds: 450));
          expect(f.actions, [id]);
          expect(feedback, findsOneWidget);
          await press.up();
          await tester.pumpAndSettle();
          expect(feedback, findsNothing);
          final cancel = await tester.startGesture(point);
          await tester.pump(const Duration(milliseconds: 650));
          await tester.pump();
          expect(feedback, findsOneWidget);
          await cancel.cancel();
          await tester.pumpAndSettle();
          expect(feedback, findsNothing);
          expect(tester.takeException(), isNull);
          f.actions.clear();
          f.actions.add(id);
          final star = find.byKey(ValueKey('$prefix-star-$id'));
          final rect = tester.getRect(star);
          expect(rect.size, const Size(48, 48));
          for (final offset in [
            const Offset(1, 1),
            const Offset(47, 1),
            const Offset(1, 47),
            const Offset(47, 47),
          ]) {
            final before = f.store.summaries
                .singleWhere((r) => r.id == id)
                .favorite;
            await tester.tapAt(rect.topLeft + offset);
            await tester.pumpAndSettle();
            expect(
              f.store.summaries.singleWhere((r) => r.id == id).favorite,
              !before,
            );
            expect(feedback, findsNothing);
          }
          final starHold = await tester.startGesture(tester.getCenter(star));
          await tester.pump(const Duration(milliseconds: 120));
          await tester.pump();
          await tester.pump(const Duration(seconds: 2));
          await starHold.up();
          await tester.pumpAndSettle();
          expect(feedback, findsNothing);
          expect(tester.takeException(), isNull);
          final data = tester.getSemantics(star).getSemanticsData();
          expect(data.label, 'Favorite Garden soup $id');
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(f.opened, isEmpty);
          expect(f.actions, [id]);
          await tester.drag(
            find.byKey(const PageStorageKey('recipes-scroll')),
            const Offset(0, -350),
          );
          await tester.pump();
          expect(feedback, findsNothing);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'A star press never paints the enclosing row, including square corners',
    (tester) async {
      tester.view.physicalSize = const Size(240, 80);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Directionality(
              textDirection: direction,
              child: RepaintBoundary(
                key: const Key('ink-capture'),
                child: Material(
                  child: Center(
                    child: SizedBox(
                      width: 200,
                      height: 53,
                      child: CompactTouchTarget(
                        trailingControl: true,
                        onTap: () {},
                        onLongPress: () {},
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  const Expanded(child: Text('Soup')),
                                  CompactTouchTarget(
                                    key: const Key('test-star'),
                                    favoriteLabel: 'Favorite Soup',
                                    onTap: () {},
                                    child: const SizedBox.square(
                                      dimension: 48,
                                      child: Icon(Icons.star),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<List<int>> rowPixels() async => (await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('ink-capture')),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData();
          image.dispose();
          final bytes = data!.buffer.asUint8List();
          final start = direction == TextDirection.ltr ? 20 : 80;
          return [
            for (var y = 15; y < 65; y++)
              for (var x = start; x < start + 120; x++)
                ...bytes.sublist((y * 240 + x) * 4, (y * 240 + x + 1) * 4),
          ];
        }))!;
        final before = await rowPixels();
        for (final corner in [const Offset(1, 1), const Offset(47, 47)]) {
          final point =
              tester.getTopLeft(find.byKey(const Key('test-star'))) + corner;
          final press = await tester.startGesture(point);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 160));
          await tester.pump(const Duration(milliseconds: 120));
          expect(
            await rowPixels(),
            before,
            reason: 'Star ink must not activate the row in $direction',
          );
          await press.up();
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'Android Compact has touch-only rows and full square favorite targets',
    (tester) async {
      final f = await _mount(tester);
      final row = visible(tester, touchRows());
      final id = idOf(tester, row, 'compact-row-');
      expect(
        find.descendant(of: row, matching: find.byType(Tooltip)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(Focus)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(MouseRegion)),
        findsNothing,
      );
      expect(
        find.descendant(of: row, matching: find.byType(InkWell)),
        findsNothing,
      );
      final star = find.byKey(ValueKey('compact-star-$id'));
      final rect = tester.getRect(star);
      expect(rect.size, const Size(48, 48));
      for (final corner in [
        const Offset(1, 1),
        const Offset(47, 1),
        const Offset(1, 47),
        const Offset(47, 47),
      ]) {
        final before = f.store.summaries
            .singleWhere((r) => r.id == id)
            .favorite;
        await tester.tapAt(rect.topLeft + corner);
        await tester.pumpAndSettle();
        expect(
          f.store.summaries.singleWhere((r) => r.id == id).favorite,
          !before,
        );
        expect(f.opened, isEmpty);
        expect(f.actions, isEmpty);
      }
      await tester.longPress(star);
      await tester.pumpAndSettle();
      expect(f.actions, isEmpty);
      expect(find.byTooltip('Favorite Garden soup $id'), findsNothing);
      final rowPoint =
          tester.getRect(find.byKey(ValueKey('compact-row-$id'))).centerLeft +
          const Offset(35, 0);
      await tester.tapAt(rowPoint);
      expect(f.opened, [id]);
      await tester.longPressAt(rowPoint);
      expect(f.actions, [id]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Android Compact keeps TalkBack row and favorite actions', (
    tester,
  ) async {
    final f = await _mount(tester);
    final row = visible(tester, touchRows());
    final id = idOf(tester, row, 'compact-row-');
    final star = find.byKey(ValueKey('compact-star-$id'));
    var node = tester.getSemantics(star);
    expect(node.getSemanticsData().label, 'Favorite Garden soup $id');
    expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
    expect(node.getSemanticsData().flagsCollection.isButton, isTrue);
    final rowData = tester.getSemantics(row).getSemanticsData();
    expect(rowData.label, contains('Garden soup $id'));
    expect(rowData.hasAction(ui.SemanticsAction.tap), isTrue);
    expect(rowData.hasAction(ui.SemanticsAction.longPress), isTrue);
    node.owner!.performAction(node.id, ui.SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(f.store.summaries.singleWhere((r) => r.id == id).favorite, isTrue);
    expect(
      tester.getSemantics(star).getSemanticsData().label,
      'Unfavorite Garden soup $id',
    );
  });

  testWidgets(
    'The stopping touch is suppressed and the immediate second tap works',
    (tester) async {
      final f = await _mount(tester);
      await _coast(tester, f);
      final row = visible(tester, touchRows());
      final id = idOf(tester, row, 'compact-row-');
      final point = tester.getRect(row).centerLeft + const Offset(35, 0);
      final stop = await tester.startGesture(point);
      await stop.up();
      expect(f.opened, isEmpty);
      expect(f.actions, isEmpty);
      await tester.tapAt(point);
      expect(f.opened, [id]);
      await tester.pumpAndSettle();
      await _coast(tester, f, start: 10000);
      final star = visible(tester, touchStars());
      final sid = idOf(tester, star, 'compact-star-');
      final corner = tester.getRect(star).topLeft + const Offset(1, 1);
      final stopStar = await tester.startGesture(corner);
      await stopStar.up();
      expect(
        f.store.summaries.singleWhere((r) => r.id == sid).favorite,
        isFalse,
      );
      await tester.tapAt(corner);
      await tester.pumpAndSettle();
      expect(
        f.store.summaries.singleWhere((r) => r.id == sid).favorite,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Selection still toggles from both the row and its checkbox', (
    tester,
  ) async {
    final f = await _mount(tester);
    f.selecting.value = true;
    await tester.pumpAndSettle();
    final row = visible(tester, touchRows());
    expect(
      find.descendant(of: row, matching: find.byType(Checkbox)),
      findsOneWidget,
    );
    expect(find.descendant(of: row, matching: touchStars()), findsNothing);
    await tester.tapAt(tester.getRect(row).centerLeft + const Offset(35, 0));
    await tester.tap(find.descendant(of: row, matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    expect(f.opened, isEmpty);
    expect(f.actions, isEmpty);
    expect(f.selectionToggles, hasLength(2));
  });

  testWidgets(
    'Windows Compact keeps its current star, tooltip and keyboard controls',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final f = await _mount(tester);
      expect(touchRows(), findsNothing);
      expect(touchStars(), findsNothing);
      final star = visible(tester, find.byType(RecipeFavoriteButton));
      expect(
        find.descendant(of: star, matching: find.byType(Tooltip)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: star, matching: find.byType(Focus)),
        findsWidgets,
      );
      debugDefaultTargetPlatformOverride = null;
      f.controller.jumpTo(0);
      await tester.pumpAndSettle();
    },
  );
}
