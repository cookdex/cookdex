import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/sync_presentation.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/sync_indicator.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

const _statuses = [
  SyncPresentation('Sync failure', syncFailureColor, 'Sync needs attention.'),
  SyncPresentation('Sync conflict', syncConflictColor, 'Choose a recipe.'),
  SyncPresentation('Not synced', syncPendingColor, 'Waiting for a device.'),
  SyncPresentation('Synced', syncCompleteColor, 'Synced with 2 devices.'),
  SyncPresentation('Sync off', syncOffColor, 'Sync is off.'),
];

Future<ScrollController> _mount(
  WidgetTester tester, {
  required double width,
  required SyncPresentation status,
  double scale = 1,
  bool empty = false,
  bool reducedMotion = false,
  VoidCallback? onSyncStatus,
  VoidCallback? onHelp,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final preferences = LocalPreferences.memory()..view = RecipeView.compact;
  final store = RecipeStore(
    FakeRepository([
      if (!empty)
        for (var i = 0; i < 80; i++)
          recipe('sync-header-$i', title: 'Synthetic recipe $i'),
    ]),
    preferences,
  );
  await store.initialize();
  final scroll = ScrollController();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    scroll.dispose();
    store.dispose();
    preferences.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: RecipesScreen(
          store: store,
          preferences: preferences,
          controller: scroll,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (_) {},
          syncStatus: status,
          onSyncStatus: onSyncStatus,
          onHelp: onHelp,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return scroll;
}

void _expectDotAndLabel(WidgetTester tester, SyncPresentation status) {
  final indicator = find.byType(SyncIndicator);
  expect(indicator.hitTestable(), findsOneWidget);
  final label = find.descendant(
    of: indicator,
    matching: find.text(status.label),
  );
  expect(label.hitTestable(), findsOneWidget);
  expect(tester.widget<Text>(label).maxLines, 1);
  final paragraph = tester.renderObject<RenderParagraph>(label);
  expect(paragraph.didExceedMaxLines, isFalse);
  final dot = find.descendant(
    of: indicator,
    matching: find.byWidgetPredicate(
      (widget) =>
          (widget is AnimatedContainer &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).shape == BoxShape.circle) ||
          (widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration! as BoxDecoration).shape == BoxShape.circle),
    ),
  );
  // AnimatedContainer builds a Container underneath it. Select the outer dot.
  final outerDot = dot.first;
  final widget = tester.widget(outerDot);
  final decoration = widget is AnimatedContainer
      ? widget.decoration! as BoxDecoration
      : (widget as Container).decoration! as BoxDecoration;
  expect(decoration.color, status.color);
  expect(tester.getSize(outerDot), const Size(7, 7));
  expect(
    tester.getRect(label).left,
    greaterThan(tester.getRect(outerDot).right),
  );
}

void main() {
  for (final width in [390.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final status in [_statuses[0], _statuses[1]]) {
        testWidgets(
          '${status.label} stays top-right after long scroll at $width dp / $scale system text',
          (tester) async {
            var taps = 0;
            final scroll = await _mount(
              tester,
              width: width,
              scale: scale,
              status: status,
              onSyncStatus: () => taps++,
            );
            _expectDotAndLabel(tester, status);
            final indicator = find.byType(SyncIndicator);
            final before = tester.getRect(indicator);
            expect(before.top, greaterThanOrEqualTo(0));
            expect(before.bottom, lessThanOrEqualTo(80));
            expect(before.right, closeTo(width - 16, 1));
            expect(tester.takeException(), isNull);

            expect(scroll.position.maxScrollExtent, greaterThan(1000));
            scroll.jumpTo(scroll.position.maxScrollExtent - 100);
            await tester.pumpAndSettle();
            expect(scroll.offset, greaterThan(1000));
            _expectDotAndLabel(tester, status);
            final after = tester.getRect(indicator);
            expect(after.top, closeTo(before.top, 1));
            expect(after.right, closeTo(before.right, 1));
            await tester.tap(find.text(status.label));
            await tester.pump();
            expect(taps, 1);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  for (final status in _statuses) {
    testWidgets('${status.label} uses a small colored dot and explicit label', (
      tester,
    ) async {
      await _mount(tester, width: 390, status: status);
      _expectDotAndLabel(tester, status);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 800.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('empty library help link works at $width dp / $scale text', (
        tester,
      ) async {
        var helpTaps = 0;
        var syncTaps = 0;
        await _mount(
          tester,
          width: width,
          scale: scale,
          status: _statuses.last,
          empty: true,
          onHelp: () => helpTaps++,
          onSyncStatus: () => syncTaps++,
        );
        expect(find.text('No recipes caught yet'), findsOneWidget);
        final help = find.widgetWithText(TextButton, 'How cookdex works');
        await tester.ensureVisible(help);
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(helpTaps, 1);
        expect(syncTaps, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('reduced motion keeps dot, label and tap action available', (
    tester,
  ) async {
    var taps = 0;
    await _mount(
      tester,
      width: 390,
      status: _statuses[1],
      reducedMotion: true,
      onSyncStatus: () => taps++,
    );
    _expectDotAndLabel(tester, _statuses[1]);
    expect(
      find.descendant(
        of: find.byType(SyncIndicator),
        matching: find.byType(AnimatedSize),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Sync conflict'));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
