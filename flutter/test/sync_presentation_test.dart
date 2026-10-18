import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/sync_presentation.dart';
import 'package:cookdex/ui/sync_indicator.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_controller_test.dart' show FakeSyncBackend;

SyncPeer _peer(String id, {bool? caughtUp, int? lastSync}) => SyncPeer(
  id: id,
  name: id,
  address: '192.0.2.1:47832',
  caughtUp: caughtUp,
  lastSync: lastSync,
);

SyncStatus _status({
  int? generation = 7,
  bool enabled = true,
  List<SyncPeer> peers = const [],
  List<SyncReport> reports = const [],
  String? error,
}) => SyncStatus(
  generation: generation,
  enabled: enabled,
  active: true,
  name: 'Synthetic phone',
  deviceId: 'synthetic-phone',
  addresses: const ['192.0.2.2'],
  port: 47832,
  peers: peers,
  reports: reports,
  error: error,
);

SyncController _controller({int Function()? currentGeneration}) {
  final controller = SyncController(
    backend: FakeSyncBackend(),
    refreshRecipes: () async {},
    isAndroid: false,
    requestPermission: () async => true,
    currentGeneration: currentGeneration,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  for (final mixed in [false, true]) {
    test(
      'unfinished pairing is neutral and never counted as synced (mixed $mixed)',
      () {
        final controller = _controller(currentGeneration: () => 7);
        const pending = SyncPeer(
          id: 'pending',
          name: 'Pending',
          address: '<lan-address>',
          pairingPending: true,
          caughtUp: true,
        );
        controller.status = _status(
          peers: [pending, if (mixed) _peer('confirmed', caughtUp: true)],
        );
        expect(syncPresentation(controller, 0).label, 'Pairing unfinished');
        expect(syncPresentation(controller, 0).color, syncPendingColor);
        expect(controller.summary, 'Pairing unfinished');
        expect(peerSyncColor(pending, controller.status!), syncPendingColor);
        expect(
          peerSyncText(pending, controller.status!),
          contains('Sync now to finish'),
        );
      },
    );
  }
  for (final message in [
    'Update cookdex on the other device to keep syncing.',
    'This device needs an update to keep syncing.',
  ]) {
    test('directional protocol advice: $message', () {
      final controller = _controller();
      final peer = _peer('tablet');
      controller.status = _status(
        peers: [peer],
        reports: [
          SyncReport(
            id: 'tablet',
            name: 'Tablet',
            status: 'error',
            error: message,
          ),
        ],
      );
      expect(syncPresentation(controller, 0).label, 'Update needed');
      expect(syncPresentation(controller, 0).sentence, message);
      expect(peerSyncText(peer, controller.status!), contains(message));
      controller.status = _status(error: message);
      expect(syncPresentation(controller, 0).sentence, message);
      controller.status = _status();
      controller.error = message;
      expect(syncPresentation(controller, 0).sentence, message);
    });
  }
  test('incompatible versions explain the required update at every error source', () {
    final controller = _controller();
    const message =
        'Incompatible LAN sync version. Update all cookdex devices, then retry.';
    for (final source in ['controller', 'status', 'report']) {
      controller.error = source == 'controller' ? message : null;
      final peer = _peer('tablet');
      controller.status = _status(
        peers: [peer],
        error: source == 'status' ? message : null,
        reports: source == 'report'
            ? const [
                SyncReport(
                  id: 'tablet',
                  name: 'Tablet',
                  status: 'error',
                  error: message,
                ),
              ]
            : const [],
      );
      final presentation = syncPresentation(controller, 2);
      expect(presentation.label, 'Update needed', reason: source);
      expect(presentation.color, syncFailureColor);
      expect(presentation.sentence, 'Update all cookdex devices, then retry.');
      if (source == 'report') {
        expect(
          peerSyncText(peer, controller.status!),
          'Update needed · update all cookdex devices',
        );
      }
    }
    controller.error = 'Update needed';
    controller.status = _status();
    expect(syncPresentation(controller, 0).label, 'Update needed');
  });

  test('failure wins over conflicts, pending changes and disabled sync', () {
    final controller = _controller(currentGeneration: () => 7);
    for (final source in ['controller', 'status', 'report']) {
      controller.error = source == 'controller' ? 'Storage unavailable' : null;
      controller.status = _status(
        enabled: false,
        error: source == 'status' ? 'Connection rejected' : null,
        peers: [_peer('tablet', caughtUp: false)],
        reports: source == 'report'
            ? const [
                SyncReport(
                  id: 'tablet',
                  name: 'Tablet',
                  status: 'error',
                  error: 'Transfer rejected',
                ),
              ]
            : const [],
      );
      final presentation = syncPresentation(controller, 2);
      expect(presentation.label, 'Sync failure', reason: source);
      expect(presentation.color, syncFailureColor, reason: source);
    }
  });

  test('conflict wins over pending, synced and off; grammar is readable', () {
    final controller = _controller(currentGeneration: () => 7);
    for (final status in [
      _status(peers: [_peer('tablet', caughtUp: false)]),
      _status(peers: [_peer('tablet', caughtUp: true)]),
      _status(enabled: false),
    ]) {
      controller.status = status;
      final presentation = syncPresentation(controller, 1);
      expect(presentation.label, 'Sync conflict');
      expect(presentation.color, syncConflictColor);
      expect(presentation.sentence, '1 recipe needs a choice.');
      expect(
        syncPresentation(controller, 2).sentence,
        '2 recipes need a choice.',
      );
    }
  });

  test('disabled, unpaired and unavailable sync show Sync off', () {
    final controller = _controller(currentGeneration: () => 7);
    for (final status in [
      null,
      _status(),
      _status(enabled: false, peers: [_peer('tablet', caughtUp: false)]),
    ]) {
      controller.status = status;
      expect(syncPresentation(controller, 0).label, 'Sync off');
      expect(syncPresentation(controller, 0).color, syncOffColor);
    }
  });

  test('every paired device must prove receipt for the current generation', () {
    final controller = _controller(currentGeneration: () => 7);
    for (final missingReceipt in [false, null]) {
      controller.status = _status(
        peers: [
          _peer('phone', caughtUp: true),
          _peer('tablet', caughtUp: missingReceipt),
          _peer('pc', caughtUp: true),
        ],
      );
      expect(
        syncPresentation(controller, 0).label,
        'Not synced',
        reason: 'caughtUp=$missingReceipt',
      );
      expect(syncPresentation(controller, 0).color, syncPendingColor);
    }
    controller.status = _status(
      generation: 6,
      peers: [_peer('tablet', caughtUp: true)],
    );
    expect(
      syncPresentation(controller, 0).label,
      'Not synced',
      reason: 'stale generation',
    );
    controller.status = _status(
      generation: null,
      peers: [_peer('tablet', caughtUp: true)],
    );
    expect(
      syncPresentation(controller, 0).label,
      'Not synced',
      reason: 'unknown receipt generation',
    );
    controller.status = _status(peers: [_peer('tablet', caughtUp: true)]);
    expect(syncPresentation(controller, 0).label, 'Synced');
  });

  test('unknown local generation never permits Synced', () {
    final controller = _controller();
    controller.status = _status(peers: [_peer('tablet', caughtUp: true)]);
    expect(syncPresentation(controller, 0).label, 'Not synced');
  });

  test('Synced sentence uses singular/plural and the least recent complete receipt', () {
    final controller = _controller(currentGeneration: () => 7);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    controller.status = _status(
      peers: [_peer('tablet', caughtUp: true, lastSync: now - 120)],
    );
    expect(
      syncPresentation(controller, 0).sentence,
      'Synced with 1 device · 2 min ago',
    );
    controller.status = _status(
      peers: [
        _peer('tablet', caughtUp: true, lastSync: now - 120),
        _peer('pc', caughtUp: true, lastSync: now - 300),
      ],
    );
    expect(
      syncPresentation(controller, 0).sentence,
      'Synced with 2 devices · 5 min ago',
    );
    controller.status = _status(peers: [_peer('tablet', caughtUp: true)]);
    expect(syncPresentation(controller, 0).sentence, 'Synced with 1 device');
  });

  testWidgets(
    'brief save grace is Syncing; missing receipt becomes Not synced after five seconds',
    (tester) async {
      var generation = 7;
      final controller = _controller(currentGeneration: () => generation);
      final backend = controller.backend as FakeSyncBackend;
      backend.current = _status(peers: [_peer('tablet', caughtUp: true)]);
      await controller.refresh();
      expect(syncPresentation(controller, 0).label, 'Synced');
      generation = 8;
      controller.collectionChanged();
      await tester.pump();
      expect(syncPresentation(controller, 0).label, 'Syncing');
      expect(syncPresentation(controller, 0).label, isNot('Synced'));
      await tester.pump(const Duration(milliseconds: 4999));
      expect(syncPresentation(controller, 0).label, 'Syncing');
      await tester.pump(const Duration(milliseconds: 1));
      expect(syncPresentation(controller, 0).label, 'Not synced');
      backend.current = _status(
        generation: 8,
        peers: [_peer('tablet', caughtUp: true)],
      );
      await controller.refresh();
      expect(syncPresentation(controller, 0).label, 'Synced');
    },
  );

  testWidgets('failures and conflicts remain visible during save grace', (
    tester,
  ) async {
    final controller = _controller(currentGeneration: () => 8);
    final backend = controller.backend as FakeSyncBackend;
    backend.current = _status(peers: [_peer('tablet', caughtUp: false)]);
    controller.collectionChanged();
    await tester.pump();
    expect(syncPresentation(controller, 1).label, 'Sync conflict');
    controller.error = 'Database unavailable';
    expect(syncPresentation(controller, 1).label, 'Sync failure');
    await tester.pump(const Duration(seconds: 5));
  });

  test('an offline waiting device is pending, with a readable retry and no failure', () {
    final controller = _controller(currentGeneration: () => 7);
    final peer = _peer('tablet', caughtUp: false);
    controller.status = _status(
      peers: [peer],
      reports: const [
        SyncReport(
          id: 'tablet',
          name: 'Tablet',
          status: 'waiting',
          retryAfterSeconds: 61,
        ),
      ],
    );
    expect(syncPresentation(controller, 0).label, 'Not synced');
    expect(
      peerSyncText(peer, controller.status!),
      'Waiting for device · retrying in 2 min',
    );
    expect(peerSyncColor(peer, controller.status!), syncPendingColor);
    expect(
      peerSyncText(
        peer,
        _status(
          peers: [peer],
          reports: const [
            SyncReport(id: 'tablet', name: 'Tablet', status: 'waiting'),
          ],
        ),
      ),
      'Waiting for device',
    );
  });

  test('peer reports are matched by ID rather than display name', () {
    final phone = _peer('phone', caughtUp: false);
    final tablet = _peer('tablet', caughtUp: false);
    final status = _status(
      peers: [phone, tablet],
      reports: const [
        SyncReport(
          id: 'phone',
          name: 'Same device name',
          status: 'waiting',
          retryAfterSeconds: 60,
        ),
        SyncReport(
          id: 'tablet',
          name: 'Same device name',
          status: 'error',
          error: 'Rejected',
        ),
      ],
    );
    expect(
      peerSyncText(phone, status),
      'Waiting for device · retrying in 1 min',
    );
    expect(peerSyncColor(phone, status), syncPendingColor);
    expect(peerSyncText(tablet, status), 'Sync failure · needs attention');
    expect(peerSyncColor(tablet, status), syncFailureColor);
  });

  test(
    'time labels use local time, relative recent times and readable dates',
    () {
      final now = DateTime(2026, 10, 9, 12, 0);
      int seconds(DateTime time) => time.toUtc().millisecondsSinceEpoch ~/ 1000;
      expect(readableSyncTime(null, now: now), 'Not synced yet');
      expect(readableSyncTime(seconds(now), now: now), 'just now');
      expect(
        readableSyncTime(
          seconds(now.subtract(const Duration(seconds: 59))),
          now: now,
        ),
        'just now',
      );
      expect(
        readableSyncTime(
          seconds(now.subtract(const Duration(seconds: 60))),
          now: now,
        ),
        '1 min ago',
      );
      expect(
        readableSyncTime(
          seconds(now.subtract(const Duration(minutes: 59))),
          now: now,
        ),
        '59 min ago',
      );
      expect(
        readableSyncTime(
          seconds(DateTime(2026, 10, 9, 7, 51)),
          now: now.toUtc(),
        ),
        'Today 7:51 AM',
      );
      expect(
        readableSyncTime(seconds(DateTime(2026, 10, 9, 0, 5)), now: now),
        'Today 12:05 AM',
      );
      expect(
        readableSyncTime(seconds(DateTime(2026, 10, 8, 12)), now: now),
        'Oct 8 · 12:00 PM',
      );
      expect(
        readableSyncTime(seconds(DateTime(2025, 12, 25, 17, 9)), now: now),
        'Dec 25, 2025 · 5:09 PM',
      );
      expect(
        readableSyncTime(seconds(now.add(const Duration(hours: 1))), now: now),
        'Today 1:00 PM',
      );
    },
  );

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'indicator keeps its right edge and honors reduced motion=$reduceMotion',
      (tester) async {
        tester.view.physicalSize = const Size(400, 200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final value = ValueNotifier(
          const SyncPresentation('Synced', syncCompleteColor, 'Synced'),
        );
        addTearDown(value.dispose);
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: cookdexTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(400, 200),
                disableAnimations: reduceMotion,
              ),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: ValueListenableBuilder<SyncPresentation>(
                    valueListenable: value,
                    builder: (context, status, _) =>
                        SyncIndicator(status: status, onTap: () => taps++),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final initialRight = tester.getRect(find.byType(TextButton)).right;
        if (reduceMotion) {
          expect(find.byType(AnimatedSize), findsNothing);
          expect(find.byType(AnimatedContainer), findsNothing);
          expect(find.byType(AnimatedSwitcher), findsNothing);
        } else {
          const duration = Duration(milliseconds: 200);
          expect(
            tester.widget<AnimatedSize>(find.byType(AnimatedSize)).duration,
            duration,
          );
          expect(
            tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .duration,
            duration,
          );
          expect(
            tester
                .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher))
                .duration,
            duration,
          );
        }
        value.value = const SyncPresentation(
          'Sync conflict',
          syncConflictColor,
          'Conflict',
        );
        await tester.pump();
        if (reduceMotion) {
          await tester.pump();
          expect(find.text('Synced'), findsNothing);
        } else {
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Synced'), findsOneWidget);
          expect(find.text('Sync conflict'), findsOneWidget);
          final transitions = tester.widgetList<FadeTransition>(
            find.descendant(
              of: find.byType(AnimatedSwitcher),
              matching: find.byType(FadeTransition),
            ),
          );
          expect(
            transitions.any(
              (fade) => fade.opacity.value > 0 && fade.opacity.value < 1,
            ),
            isTrue,
          );
          final dot = tester.widget<DecoratedBox>(
            find.descendant(
              of: find.byType(AnimatedContainer),
              matching: find.byType(DecoratedBox),
            ),
          );
          final color = (dot.decoration as BoxDecoration).color;
          expect(color, isNot(syncCompleteColor));
          expect(color, isNot(syncConflictColor));
        }
        expect(
          tester.getRect(find.byType(TextButton)).right,
          closeTo(initialRight, 0.01),
        );
        await tester.pumpAndSettle();
        expect(find.text('Synced'), findsNothing);
        expect(
          tester.getRect(find.byType(TextButton)).right,
          closeTo(initialRight, 0.01),
        );
        await tester.tap(find.byType(TextButton));
        expect(taps, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
