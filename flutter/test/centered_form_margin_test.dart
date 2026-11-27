import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/pairing_invitation_qr.dart';
import 'package:cookdex/ui/pairing_screen.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' as editor_fixture;
import 'sync_controller_test.dart' show FakeSyncBackend;

Future<void> _scrollMargins(
  WidgetTester tester,
  Finder scroll,
  double contentWidth,
) async {
  final viewport = tester.getRect(scroll);
  final position = tester
      .state<ScrollableState>(
        find.descendant(of: scroll, matching: find.byType(Scrollable)).first,
      )
      .position;
  expect(position.maxScrollExtent, greaterThan(0));
  final margin = (viewport.width - contentWidth) / 2;
  expect(margin, greaterThan(16));
  for (final x in [viewport.left + margin / 2, viewport.right - margin / 2]) {
    final point = Offset(x, viewport.center.dy);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.dragFrom(point, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: point,
        scrollDelta: const Offset(0, 140),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
  }
  expect(tester.takeException(), isNull);
}

void main() {
  for (final (name, size, platform) in [
    ('Windows', const Size(1800, 600), TargetPlatform.windows),
    ('landscape tablet', const Size(1280, 600), TargetPlatform.android),
  ]) {
    Future<void> mount(WidgetTester tester, Widget child) async {
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

    testWidgets('$name Pairing scrolls from both centered margins', (
      tester,
    ) async {
      final backend = FakeSyncBackend();
      final sync = SyncController(
        backend: backend,
        refreshRecipes: () async {},
        isAndroid: platform == TargetPlatform.android,
        requestPermission: () async => true,
      );
      try {
        // Android invitation creation requires an actually resumed host.
        // Refreshing status alone leaves the fixture paused, without its QR.
        await sync.lifecycle(true);
        await mount(tester, PairingScreen(controller: sync));
        await tester.tap(find.text('Invite a device'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('New invitation'));
        await tester.pumpAndSettle();
        expect(backend.invitationAddresses, hasLength(1));
        expect(find.byType(PairingInvitationQr), findsOneWidget);
        final scroll = find.byWidgetPredicate((widget) => widget is ListView);
        expect(tester.getRect(scroll).width, size.width);
        await _scrollMargins(tester, scroll, 640);
        expect(backend.invitationAddresses, hasLength(1));
        expect(backend.pairCodes, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        sync.dispose();
      }
    });

    testWidgets('$name Recipe editor scrolls from both centered margins', (
      tester,
    ) async {
      final (controller, _, _) = await editor_fixture.controller();
      controller.draft.title = 'Garden vegetable soup';
      await mount(tester, RecipeEditor(controller: controller));
      final scroll = find.byWidgetPredicate(
        (widget) => widget is CustomScrollView,
      );
      expect(tester.getRect(scroll).width, size.width);
      final title = tester.getRect(find.byKey(const ValueKey('title')));
      expect(title.left, closeTo((size.width - 760) / 2, .01));
      expect(title.width, closeTo(760, .01));
      await _scrollMargins(tester, scroll, 760);
      expect(controller.draft.title, 'Garden vegetable soup');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
