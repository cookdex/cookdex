import 'dart:async';

import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'sync_controller_test.dart' show FakeSyncBackend, syncStatus;

class _GatedSyncBackend extends FakeSyncBackend {
  final activationStarted = Completer<void>();
  final activationGate = Completer<void>();
  int inFlight = 0;
  int maxInFlight = 0;
  bool? lastCompletedActive;

  @override
  Future<void> hostActive(bool active) async {
    activeCalls.add(active);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    if (active) {
      activationStarted.complete();
      await activationGate.future;
    }
    lastCompletedActive = active;
    inFlight--;
  }
}

const _availabilityFailure = 'Synthetic host activation failed.';

class _FailingHostSyncBackend extends FakeSyncBackend {
  Object? hostError;
  final completedActiveCalls = <bool>[];

  @override
  Future<void> hostActive(bool active) async {
    activeCalls.add(active);
    if (hostError != null) throw hostError!;
    completedActiveCalls.add(active);
  }
}

void main() {
  late FakeSyncBackend backend;
  late SyncController controller;
  late bool permission;
  late int checkCalls;
  late int requestCalls;
  late bool controllerDisposed;
  Completer<bool>? checkGate;
  Completer<bool>? requestGate;

  void create({bool android = true, FakeSyncBackend? suppliedBackend}) {
    backend = suppliedBackend ?? FakeSyncBackend();
    controller = SyncController(
      backend: backend,
      refreshRecipes: () async {},
      isAndroid: android,
      checkPermission: () async {
        checkCalls++;
        return checkGate?.future ?? permission;
      },
      requestPermission: () async {
        requestCalls++;
        return requestGate?.future ?? permission;
      },
    );
    addTearDown(() {
      if (!controllerDisposed) controller.dispose();
    });
  }

  Future<void> choosePairingPath(WidgetTester tester, String action) async {
    await tester.tap(
      find.text(action == 'Pair' ? 'Join a device' : 'Invite a device'),
    );
    await tester.pumpAndSettle();
    if (action == 'Pair' && controller.isAndroid) {
      await tester.tap(find.widgetWithText(TextButton, 'Paste invitation'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpPairing(
    WidgetTester tester, {
    String action = 'New invitation',
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: PairingScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();
    await choosePairingPath(tester, action);
  }

  setUp(() {
    permission = true;
    checkCalls = 0;
    requestCalls = 0;
    controllerDisposed = false;
    checkGate = null;
    requestGate = null;
  });

  test(
    'resumed persisted sync pauses without permission or a prompt',
    () async {
      create();
      final saved = backend.current;
      permission = false;
      await controller.lifecycle(true);

      expect(checkCalls, 1);
      expect(requestCalls, 0);
      expect(backend.activeCalls, [false]);
      expect(backend.configureCalls, isEmpty);
      expect(controller.status!.enabled, isTrue);
      expect(controller.status!.name, saved.name);
      expect(controller.error, SyncController.permissionMessage);
      expect(controller.summary, SyncController.permissionMessage);
    },
  );

  test(
    'permission revocation is rechecked on resume while sync stays saved',
    () async {
      create();
      await controller.lifecycle(true);
      await controller.lifecycle(false);
      permission = false;
      await controller.lifecycle(true);

      expect(checkCalls, 3);
      expect(requestCalls, 0);
      expect(backend.activeCalls, [true, false, false]);
      expect(backend.configureCalls, isEmpty);
      expect(controller.status!.enabled, isTrue);
      expect(controller.error, SyncController.permissionMessage);
    },
  );

  test('disabled sync does not report missing permission on resume', () async {
    create();
    backend.current = syncStatus(enabled: false, active: false);
    permission = false;
    await controller.lifecycle(true);

    expect(backend.activeCalls, [false]);
    expect(requestCalls, 0);
    expect(controller.error, isNull);
    expect(controller.summary, 'Off');
  });

  test('granting permission through Sync now resumes persisted sync', () async {
    create();
    final saved = backend.current;
    permission = false;
    await controller.lifecycle(true);
    expect(controller.error, SyncController.permissionMessage);

    permission = true;
    await controller.manual();

    expect(requestCalls, 1);
    expect(backend.activeCalls, [false, true]);
    expect(backend.syncCalls, 1);
    expect(backend.configureCalls, isEmpty);
    expect(controller.status!.enabled, saved.enabled);
    expect(controller.status!.name, saved.name);
    expect(controller.error, isNull);
    expect(controller.busy, isFalse);
  });

  test('granting permission in settings clears the error on resume', () async {
    create();
    permission = false;
    await controller.lifecycle(true);
    await controller.lifecycle(false);
    permission = true;
    await controller.lifecycle(true);

    expect(backend.activeCalls, [false, false, true]);
    expect(requestCalls, 0);
    expect(backend.configureCalls, isEmpty);
    expect(controller.error, isNull);
  });

  test(
    'denied Sync now rechecks already enabled sync without an exchange',
    () async {
      create();
      await controller.lifecycle(true);
      permission = false;
      await controller.manual();

      expect(requestCalls, 1);
      expect(backend.activeCalls, [true, false]);
      expect(backend.syncCalls, 0);
      expect(backend.configureCalls, isEmpty);
      expect(controller.status!.enabled, isTrue);
      expect(controller.error, SyncController.permissionMessage);
      expect(controller.busy, isFalse);
    },
  );

  test('delayed permission check observes a newer Android pause', () async {
    create();
    checkGate = Completer<bool>();
    final resume = controller.lifecycle(true);
    await Future<void>.delayed(Duration.zero);
    expect(checkCalls, 1);
    final pause = controller.lifecycle(false);
    checkGate!.complete(true);
    await Future.wait([resume, pause]);

    expect(backend.activeCalls, [false, false]);
    expect(requestCalls, 0);
  });

  testWidgets(
    'a prompt granted while Android stays paused times out without syncing',
    (tester) async {
      create();
      await controller.lifecycle(true);
      requestGate = Completer<bool>();
      final action = controller.manual();
      expect(requestCalls, 1);
      await controller.lifecycle(false);
      requestGate!.complete(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      expect(controller.busy, isTrue);
      expect(backend.syncCalls, 0);
      expect(backend.activeCalls, [true, false]);
      await tester.pump(const Duration(seconds: 1));
      await action;

      expect(backend.activeCalls, [true, false]);
      expect(backend.syncCalls, 0);
      expect(backend.configureCalls, isEmpty);
      expect(controller.error, 'Sync paused. Return to the app and retry.');
      expect(controller.busy, isFalse);
      await controller.lifecycle(true);
      await tester.pump();
      expect(backend.syncCalls, 0);
      expect(controller.busy, isFalse);
      await controller.lifecycle(false);
    },
  );

  testWidgets('first invitation waits for resume after the permission grant', (
    tester,
  ) async {
    create();
    final saved = backend.current;
    permission = false;
    await controller.lifecycle(false);
    requestGate = Completer<bool>();
    await pumpPairing(tester);
    await tester.tap(find.text('New invitation'));
    await tester.pump();
    permission = true;
    requestGate!.complete(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(requestCalls, 1);
    expect(backend.activeCalls, [false]);
    expect(backend.invitationAddresses, isEmpty);
    expect(find.text('Copy invitation'), findsNothing);
    await controller.lifecycle(true);
    await tester.pumpAndSettle();

    expect(backend.activeCalls.last, isTrue);
    expect(backend.invitationAddresses, ['192.168.1.4']);
    expect(backend.configureCalls, isEmpty);
    expect(controller.status!.enabled, saved.enabled);
    expect(controller.status!.name, saved.name);
    expect(controller.error, isNull);
    expect(find.byType(PrettyQrView), findsOneWidget);
    expect(find.text('recipe-pair:synthetic-secret-1'), findsNothing);
    expect(find.text('Copy invitation'), findsOneWidget);
    await controller.lifecycle(false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing while waiting for resume stops the pending action', (
    tester,
  ) async {
    create();
    await controller.lifecycle(false);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final action = controller.manual();
    await tester.pump();
    expect(controller.busy, isTrue);
    expect(backend.syncCalls, 0);
    final beforeDispose = notifications;
    controller.dispose();
    controllerDisposed = true;
    await tester.pump();
    await action;
    await tester.pump(const Duration(seconds: 5));

    expect(backend.activeCalls, [false]);
    expect(backend.syncCalls, 0);
    expect(controller.error, 'Sync screen closed.');
    expect(controller.busy, isFalse);
    expect(notifications, beforeDispose);
    expect(tester.takeException(), isNull);
  });

  test('pause queues behind an in-flight granted host activation', () async {
    final gated = _GatedSyncBackend();
    create(suppliedBackend: gated);
    permission = false;
    await controller.lifecycle(true);
    permission = true;
    final action = controller.manual();
    await gated.activationStarted.future;

    final pause = controller.lifecycle(false);
    await Future<void>.delayed(Duration.zero);
    expect(gated.activeCalls, [false, true]);
    expect(gated.inFlight, 1);
    gated.activationGate.complete();
    await Future.wait([action, pause]);

    expect(gated.activeCalls, [false, true, false]);
    expect(gated.maxInFlight, 1);
    expect(gated.lastCompletedActive, isFalse);
  });

  test(
    'host activation failure stops Sync now and lifecycle can recover',
    () async {
      final failing = _FailingHostSyncBackend();
      create(suppliedBackend: failing);
      await controller.lifecycle(true);
      failing.hostError = StateError(_availabilityFailure);
      await controller.manual();

      expect(backend.syncCalls, 0);
      expect(backend.configureCalls, isEmpty);
      expect(controller.error, _availabilityFailure);
      expect(controller.busy, isFalse);
      expect(failing.completedActiveCalls, [true]);

      failing.hostError = null;
      await controller.lifecycle(false);
      await controller.lifecycle(true);
      expect(failing.completedActiveCalls, [true, false, true]);
      await controller.manual();
      expect(backend.syncCalls, 1);
      expect(controller.error, isNull);
    },
  );

  test(
    'Windows lifecycle remains active without Android permission checks',
    () async {
      create(android: false);
      permission = false;
      await controller.lifecycle(true);
      await controller.lifecycle(false);

      expect(checkCalls, 0);
      expect(requestCalls, 0);
      expect(backend.activeCalls, [true, true]);
      expect(controller.error, isNull);
    },
  );

  for (final action in ['New invitation', 'Pair']) {
    testWidgets(
      'host activation failure stops $action and lifecycle recovers',
      (tester) async {
        final failing = _FailingHostSyncBackend();
        create(suppliedBackend: failing);
        await controller.lifecycle(true);
        await pumpPairing(tester, action: action);
        if (action == 'Pair') {
          await tester.enterText(
            find.byType(TextField),
            'recipe-pair:synthetic-input',
          );
        }
        failing.hostError = StateError(_availabilityFailure);
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();

        expect(requestCalls, 1);
        expect(backend.invitationAddresses, isEmpty);
        expect(backend.pairCodes, isEmpty);
        expect(backend.syncCalls, 0);
        expect(backend.configureCalls, isEmpty);
        expect(find.text(_availabilityFailure), findsOneWidget);
        expect(find.byType(PairingScreen), findsOneWidget);
        expect(controller.busy, isFalse);
        expect(failing.completedActiveCalls, [true]);

        failing.hostError = null;
        await controller.lifecycle(false);
        await controller.lifecycle(true);
        expect(failing.completedActiveCalls, [true, false, true]);
        await controller.lifecycle(false);
      },
    );

    testWidgets('denied $action sends no network request and allows a retry', (
      tester,
    ) async {
      create();
      await controller.lifecycle(true);
      permission = false;
      await pumpPairing(tester, action: action);
      if (action == 'Pair') {
        await tester.enterText(
          find.byType(TextField),
          'recipe-pair:synthetic-input',
        );
      }
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      expect(requestCalls, 1);
      expect(backend.activeCalls, [true, false]);
      expect(backend.invitationAddresses, isEmpty);
      expect(backend.pairCodes, isEmpty);
      expect(backend.syncCalls, 0);
      expect(backend.configureCalls, isEmpty);
      expect(find.text(SyncController.permissionMessage), findsOneWidget);
      expect(find.byType(PairingScreen), findsOneWidget);
      expect(controller.busy, isFalse);
      if (action == 'Pair') {
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'recipe-pair:synthetic-input',
        );
      }
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(action),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      await controller.lifecycle(false);
    });
  }

  testWidgets(
    'granting New invitation access resumes without rewriting setup',
    (tester) async {
      create();
      final saved = backend.current;
      permission = false;
      await controller.lifecycle(true);
      await pumpPairing(tester);
      expect(find.text(SyncController.permissionMessage), findsOneWidget);

      permission = true;
      await tester.tap(find.text('New invitation'));
      await tester.pumpAndSettle();

      expect(requestCalls, 1);
      expect(backend.activeCalls, [false, true]);
      expect(backend.invitationAddresses, ['192.168.1.4']);
      expect(backend.configureCalls, isEmpty);
      expect(controller.status!.enabled, saved.enabled);
      expect(controller.status!.name, saved.name);
      expect(controller.error, isNull);
      expect(find.text(SyncController.permissionMessage), findsNothing);
      expect(find.byType(PrettyQrView), findsOneWidget);
      expect(find.text('recipe-pair:synthetic-secret-1'), findsNothing);
      expect(find.text('Copy invitation'), findsOneWidget);
      await controller.lifecycle(false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('granting Pair access resumes and closes the pairing route', (
    tester,
  ) async {
    create();
    final saved = backend.current;
    permission = false;
    await controller.lifecycle(true);
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => PairingScreen(controller: controller),
                ),
              ),
              child: const Text('Open pairing'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open pairing'));
    await tester.pumpAndSettle();
    await choosePairingPath(tester, 'Pair');
    await tester.enterText(
      find.byType(TextField),
      'recipe-pair:synthetic-input',
    );
    permission = true;
    await tester.ensureVisible(find.text('Pair'));
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();

    expect(requestCalls, 1);
    expect(backend.activeCalls, [false, true]);
    expect(backend.pairCodes, ['recipe-pair:synthetic-input']);
    expect(backend.configureCalls, isEmpty);
    expect(controller.status!.enabled, saved.enabled);
    expect(controller.status!.name, saved.name);
    expect(controller.error, isNull);
    expect(find.byType(PairingScreen), findsNothing);
    expect(find.text('Open pairing'), findsOneWidget);
    await controller.lifecycle(false);
  });
}
