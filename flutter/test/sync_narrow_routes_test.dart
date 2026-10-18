import 'dart:io';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;
import 'sync_controller_test.dart' show FakeSyncBackend, syncStatus;

class _Repository extends FakeRepository {
  _Repository() : super([]);
  @override
  CollectionSnapshot get current => CollectionSnapshot(
    setAsideCount: 0,
    generation: 0,
    summaries: const [],
    shopping: const [],
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    hasPrevious: false,
    conflicts: [
      Conflict(
        recipeId: 'soup',
        versions: [
          ConflictVersion(
            id: 'live',
            recipe: recipe('soup', title: 'Garden vegetable soup'),
          ),
          const ConflictVersion(id: 'deleted', deletedAt: '2026-10-15'),
        ],
      ),
    ],
  );
}

Future<void> _visible(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _visible(tester, target);
  final rect = tester.getRect(target);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(320));
  expect(target.hitTestable(), findsOneWidget);
  expect(tester.takeException(), isNull);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final route in ['pairing', 'device', 'conflicts']) {
      testWidgets(
        '320dp text $scale: $route subroute fits and actions remain reachable',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(320, 780);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.runAsync(() async {
            final sdk =
                Platform.environment['FLUTTER_SDK'] ??
                (throw StateError('Set FLUTTER_SDK before running font tests'));
            final loader = FontLoader('Roboto');
            for (final weight in ['regular', 'bold']) {
              loader.addFont(
                File(
                  '$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf',
                ).readAsBytes().then(ByteData.sublistView),
              );
            }
            await loader.load();
          });
          final prefs = LocalPreferences.memory();
          final store = RecipeStore(_Repository(), prefs);
          await store.initialize();
          final backend = FakeSyncBackend();
          backend.current = syncStatus(
            peers: const [
              SyncPeer(
                id: 'tablet',
                name: 'Kitchen tablet with a comfortably long device name',
                address: '192.0.2.123:47832',
                caughtUp: true,
              ),
            ],
          );
          final controller = SyncController(
            backend: backend,
            refreshRecipes: store.refresh,
            isAndroid: true,
            requestPermission: () async => true,
          );
          await controller.lifecycle(true);
          Future<void> mount(Widget screen) async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              MaterialApp(
                theme: cookdexTheme().copyWith(
                  platform: TargetPlatform.android,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: screen,
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }

          try {
            if (route == 'pairing') {
              await mount(PairingScreen(controller: controller));
              await _tap(tester, find.text('Join a device'));
              await _visible(
                tester,
                find.widgetWithText(FilledButton, 'Scan QR code'),
              );
              final scan = tester.getRect(
                find.widgetWithText(FilledButton, 'Scan QR code'),
              );
              expect(scan.right, lessThanOrEqualTo(320));
              expect(scan.height, greaterThanOrEqualTo(48));
              await _tap(
                tester,
                find.widgetWithText(TextButton, 'Paste invitation'),
              );
              await _visible(tester, find.byType(TextField));
              await tester.enterText(
                find.byType(TextField),
                'recipe-pair:synthetic',
              );
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              final pair = find.widgetWithText(FilledButton, 'Pair');
              await _visible(tester, pair);
              expect(pair.hitTestable(), findsOneWidget);
              expect(tester.getRect(pair).right, lessThanOrEqualTo(320));
              await mount(PairingScreen(controller: controller));
              await _tap(tester, find.text('Invite a device'));
              await _tap(
                tester,
                find.widgetWithText(FilledButton, 'New invitation'),
              );
              await _visible(tester, find.byType(PrettyQrView));
              expect(
                tester.getRect(find.byType(PrettyQrView)).right,
                lessThanOrEqualTo(320),
              );
              await _tap(
                tester,
                find.widgetWithText(TextButton, 'Copy invitation'),
              );
            } else if (route == 'device') {
              await mount(
                SyncDeviceDetailsScreen(
                  controller: controller,
                  deviceId: 'tablet',
                ),
              );
              await _visible(tester, find.text('192.0.2.123:47832'));
              expect(
                tester.getRect(find.text('192.0.2.123:47832')).right,
                lessThanOrEqualTo(320),
              );
              await _tap(tester, find.text('Forget device'));
              await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
              expect(backend.forgotten, isEmpty);
            } else {
              await mount(
                ConflictsScreen(controller: controller, store: store),
              );
              await _tap(tester, find.textContaining('Version 1').first);
              await _tap(
                tester,
                find.widgetWithText(TextButton, 'Use version'),
              );
              await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
              await _tap(tester, find.textContaining('Version 2').first);
              await _tap(
                tester,
                find.widgetWithText(TextButton, 'Use deletion'),
              );
              await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
              await _tap(tester, find.widgetWithText(TextButton, 'Keep all'));
              await _tap(tester, find.widgetWithText(TextButton, 'Cancel'));
              expect(backend.resolutions, isEmpty);
            }
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await controller.lifecycle(false);
            controller.dispose();
            store.dispose();
            prefs.dispose();
          }
        },
      );
    }
  }
}
