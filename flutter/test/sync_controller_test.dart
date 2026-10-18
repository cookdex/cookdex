import 'dart:async';

import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';

SyncStatus syncStatus({
  bool enabled = true,
  bool active = true,
  bool rePairRequired = false,
  String? invitationId,
  List<SyncPeer> peers = const [],
  List<SyncReport> reports = const [],
  List<String> addresses = const ['192.168.1.4'],
  String? error,
  int? generation,
}) => SyncStatus(
  enabled: enabled,
  active: active,
  rePairRequired: rePairRequired,
  name: 'Phone <test>',
  deviceId: 'synthetic-device',
  addresses: addresses,
  port: 47831,
  invitationId: invitationId,
  peers: peers,
  reports: reports,
  error: error,
  generation: generation,
);

class FakeSyncBackend extends SyncBackend {
  SyncStatus current = syncStatus();
  final activeCalls = <bool>[];
  final configureCalls = <(bool, String)>[];
  final pairingCalls = <bool>[];
  final invitationAddresses = <String>[];
  final pairCodes = <String>[];
  final forgotten = <String>[];
  final resolutions = <(Conflict, ConflictChoice)>[];
  int statusCalls = 0;
  int syncCalls = 0;
  int noticeDismissals = 0;
  @override
  Future<void> dismissPairingNotice() async {
    noticeDismissals++;
    current = syncStatus();
  }

  Completer<void>? syncGate;
  Completer<SyncStatus>? statusGate;
  Object? statusError;
  Object? pairError;
  Future<void> Function(Conflict, ConflictChoice)? onResolve;

  @override
  Future<SyncStatus> status() async {
    statusCalls++;
    if (statusError != null) throw statusError!;
    return statusGate?.future ?? current;
  }

  @override
  Future<void> hostActive(bool active) async => activeCalls.add(active);
  @override
  Future<void> configure(bool enabled, String name) async {
    configureCalls.add((enabled, name));
    current = syncStatus(enabled: enabled);
  }

  @override
  Future<void> pairing(bool active) async => pairingCalls.add(active);
  @override
  Future<String> invitation(String address) async {
    invitationAddresses.add(address);
    current = syncStatus(
      invitationId: 'invitation-${invitationAddresses.length}',
    );
    return 'recipe-pair:synthetic-secret-${invitationAddresses.length}';
  }

  @override
  Future<void> pair(String code) async {
    pairCodes.add(code);
    if (pairError != null) throw pairError!;
  }

  @override
  Future<void> forget(String id) async => forgotten.add(id);
  @override
  Future<void> sync() async {
    syncCalls++;
    await syncGate?.future;
  }

  @override
  Future<void> resolve(Conflict conflict, ConflictChoice choice) async {
    resolutions.add((conflict, choice));
    await onResolve?.call(conflict, choice);
  }
}

void main() {
  late FakeSyncBackend backend;
  late SyncController controller;
  late int recipeRefreshes;
  late int permissionCalls;
  var permission = true;
  var disposed = false;

  void create({bool android = true}) {
    backend = FakeSyncBackend();
    recipeRefreshes = 0;
    permissionCalls = 0;
    disposed = false;
    controller = SyncController(
      backend: backend,
      refreshRecipes: () async {
        recipeRefreshes++;
      },
      isAndroid: android,
      requestPermission: () async {
        permissionCalls++;
        return permission;
      },
    );
    addTearDown(() {
      if (!disposed) controller.dispose();
    });
  }

  setUp(() => permission = true);

  testWidgets('Windows stays active and polls status while hidden', (
    tester,
  ) async {
    create(android: false);
    await controller.lifecycle(true);
    await controller.lifecycle(false);
    expect(backend.activeCalls, [true, true]);
    final initial = backend.statusCalls;
    await tester.pump(const Duration(seconds: 1));
    expect(backend.statusCalls, initial);
    await tester.pump(const Duration(seconds: 1));
    expect(backend.statusCalls, initial + 1);
    expect(recipeRefreshes, backend.statusCalls);
    controller.dispose();
    disposed = true;
    // Disposal cancels the status timer.
    await tester.pump(const Duration(seconds: 30));
    expect(backend.statusCalls, initial + 1);
  });

  testWidgets('Android pauses status polling until resumed', (tester) async {
    create();
    await controller.lifecycle(true);
    await tester.pump(const Duration(seconds: 2));
    expect(backend.statusCalls, 2);
    await controller.lifecycle(false);
    final pausedCalls = backend.statusCalls;
    await tester.pump(const Duration(seconds: 45));
    expect(backend.statusCalls, pausedCalls);
    await controller.lifecycle(true);
    await tester.pump(const Duration(seconds: 2));
    expect(backend.activeCalls, [true, false, true]);
    expect(backend.statusCalls, pausedCalls + 2);
    controller.dispose();
    disposed = true;
  });

  test('queued resume cannot reactivate Android after a newer pause', () async {
    create();
    final resume = controller.lifecycle(true);
    final pause = controller.lifecycle(false);
    await Future.wait([resume, pause]);
    expect(backend.activeCalls.last, isFalse);
  });

  test('denied local network permission keeps sync disabled', () async {
    create();
    backend.current = syncStatus(enabled: false);
    permission = false;
    await controller.configure(true, 'Phone');
    expect(permissionCalls, 1);
    expect(backend.configureCalls, isEmpty);
    expect(controller.status!.enabled, isFalse);
    expect(controller.error, SyncController.permissionMessage);
    expect(controller.busy, isFalse);
    await controller.configure(false, 'Phone');
    expect(permissionCalls, 1);
    expect(backend.configureCalls, [(false, 'Phone')]);
    expect(controller.error, isNull);
  });

  test(
    'summary distinguishes off, paused, unpaired and paired states',
    () async {
      create();
      expect(controller.summary, 'Off');
      for (final entry in [
        (syncStatus(enabled: false), 'Off'),
        (syncStatus(active: false), 'Paused'),
        (syncStatus(), 'No paired devices'),
        (
          syncStatus(
            peers: const [
              SyncPeer(
                id: 'tablet',
                name: 'Tablet',
                address: '192.168.1.5:47831',
              ),
            ],
          ),
          '1 paired device',
        ),
      ]) {
        backend.current = entry.$1;
        await controller.refresh();
        expect(controller.summary, entry.$2);
      }
    },
  );

  test(
    'busy actions cannot start duplicate exchanges and refresh on completion',
    () async {
      create();
      await controller.lifecycle(true);
      recipeRefreshes = 0;
      backend.syncGate = Completer<void>();
      final first = controller.manual();
      expect(controller.busy, isTrue);
      expect(controller.summary, 'Syncing…');
      // Permission and lifecycle readiness are checked before the exchange.
      await Future<void>.delayed(Duration.zero);
      await controller.manual();
      await controller.forget('tablet');
      expect(backend.syncCalls, 1);
      expect(backend.forgotten, isEmpty);
      backend.syncGate!.complete();
      await first;
      expect(controller.busy, isFalse);
      expect(recipeRefreshes, 2);
    },
  );

  test('overlapping refreshes share a single status request', () async {
    create();
    backend.statusGate = Completer<SyncStatus>();
    final first = controller.refresh();
    await controller.refresh();
    expect(backend.statusCalls, 1);
    backend.statusGate!.complete(syncStatus());
    await first;
    expect(recipeRefreshes, 1);
  });

  test(
    'unchanged status polls avoid collection loads and recover polling errors',
    () async {
      final backend = FakeSyncBackend()..current = syncStatus(generation: 7);
      var loads = 0;
      final controller = SyncController(
        backend: backend,
        refreshRecipes: () async {
          loads++;
        },
        isAndroid: true,
        requestPermission: () async => true,
        currentGeneration: () => 7,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(loads, 0);
      expect(controller.receiptsCurrent, isTrue);
      backend.statusError = StateError('Storage temporarily unavailable');
      await controller.refresh();
      expect(controller.error, 'Storage temporarily unavailable');
      backend.statusError = null;
      backend.current = syncStatus(generation: 8);
      await controller.refresh();
      expect(loads, 1);
      expect(controller.error, isNull);
      expect(controller.receiptsCurrent, isFalse);
    },
  );

  test(
    'typed errors preserve useful messages and unknown errors are safe',
    () async {
      create();
      backend.statusError = const ServiceError(
        code: ErrorCode.validation,
        message: 'Authentication failed',
      );
      await controller.refresh();
      expect(controller.error, 'Authentication failed');
      expect(controller.summary, 'Authentication failed');
      expect(
        SyncController.message(Exception('synthetic-secret')),
        'Sync could not complete. Check the local network and try again.',
      );
    },
  );
}
