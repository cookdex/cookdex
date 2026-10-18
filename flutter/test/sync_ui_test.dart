import 'dart:async';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/sync_presentation.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;
import 'sync_controller_test.dart' show FakeSyncBackend, syncStatus;

class _ConflictRepository extends FakeRepository {
  _ConflictRepository() : super([]);
  List<Conflict> conflicts = [];
  @override
  CollectionSnapshot get current => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: generation,
    summaries: const [],
    shopping: const [],
    conflicts: conflicts,
    hasPrevious: false,
  );
}

Conflict _conflict({String liveId = 'live', int revision = 1}) => Conflict(
  recipeId: 'cake',
  versions: [
    ConflictVersion(
      id: liveId,
      recipe: recipe('cake', revision: revision),
    ),
    const ConflictVersion(id: 'deleted', deletedAt: '2026-10-02'),
  ],
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 1200);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(theme: cookdexTheme(), home: child));
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 300);
  } else {
    await tester.ensureVisible(target);
  }
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(of: find.byType(AlertDialog), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  late FakeSyncBackend backend;
  late SyncController controller;
  late _ConflictRepository repository;
  late RecipeStore store;
  late LocalPreferences prefs;

  setUp(() async {
    backend = FakeSyncBackend();
    repository = _ConflictRepository();
    prefs = LocalPreferences.memory();
    store = RecipeStore(repository, prefs);
    await store.initialize();
  });

  void syncWidgets(
    String description,
    Future<void> Function(WidgetTester) test,
  ) {
    testWidgets(description, (tester) async {
      // Lifecycle futures must be created in the widget test's fake async zone.
      controller = SyncController(
        backend: backend,
        refreshRecipes: store.refresh,
        isAndroid: true,
        requestPermission: () async => true,
      );
      await controller.lifecycle(true);
      try {
        await test(tester);
      } finally {
        await controller.lifecycle(false);
        controller.dispose();
      }
    });
  }

  tearDown(() {
    store.dispose();
    prefs.dispose();
  });

  syncWidgets('re-pair notice persists until its explicit dismissal', (
    tester,
  ) async {
    backend.current = syncStatus(rePairRequired: true);
    await controller.refresh();
    await _pump(tester, SyncScreen(controller: controller, store: store));
    expect(find.text('Pair your devices again'), findsOneWidget);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Pair your devices again'), findsOneWidget);
    expect(backend.noticeDismissals, 0);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(backend.noticeDismissals, 1);
    expect(find.text('Pair your devices again'), findsNothing);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Pair your devices again'), findsNothing);
  });

  for (final mixed in [false, true]) {
    syncWidgets(
      'unfinished pairing has separate group and Forget setup (mixed $mixed)',
      (tester) async {
        backend.current = syncStatus(
          peers: [
            const SyncPeer(
              id: 'pending',
              name: 'Unfinished tablet',
              address: '<lan-address>',
              pairingPending: true,
            ),
            if (mixed)
              const SyncPeer(
                id: 'confirmed',
                name: 'Confirmed device',
                address: '<lan-address>',
                caughtUp: true,
              ),
          ],
        );
        await controller.refresh();
        await _pump(tester, SyncScreen(controller: controller, store: store));
        expect(find.text('Pairing unfinished'), findsOneWidget);
        expect(find.text('Synced'), findsNothing);
        expect(
          find.text('No devices paired yet'),
          mixed ? findsNothing : findsOneWidget,
        );
        final add = find.byKey(const ValueKey('sync-add-device'));
        await _reveal(tester, add);
        expect(tester.widget<ListTile>(add).onTap, isNotNull);
        final pairedCard = find.ancestor(of: add, matching: find.byType(Card));
        expect(
          find.descendant(
            of: pairedCard,
            matching: find.text('Unfinished tablet'),
          ),
          findsNothing,
        );
        final row = find.byKey(const ValueKey('sync-peer-pending'));
        await _reveal(tester, row);
        expect(find.text('Unfinished pairing'), findsOneWidget);
        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(find.text('Last sync'), findsNothing);
        await tester.tap(find.text('Forget setup'));
        await _confirm(tester, 'Cancel');
        expect(backend.forgotten, isEmpty);
        await tester.tap(find.text('Forget setup'));
        await _confirm(tester, 'Forget');
        expect(backend.forgotten, ['pending']);
      },
    );
  }

  syncWidgets('peer details and diagnostics require a tap; forget confirms', (
    tester,
  ) async {
    backend.current = syncStatus(
      peers: const [
        SyncPeer(
          id: 'tablet',
          name: 'Tablet <other>',
          address: '192.168.1.5:47831',
          lastSync: 1791504000,
        ),
      ],
    );
    await controller.refresh();
    await _pump(tester, SyncScreen(controller: controller, store: store));
    expect(find.text('Phone <test>'), findsOneWidget);
    expect(find.text('Tablet <other>'), findsOneWidget);
    expect(find.text('192.168.1.5:47831'), findsNothing);
    expect(find.textContaining('synthetic-device'), findsNothing);
    expect(find.textContaining('.000'), findsNothing);
    await tester.tap(find.text('Tablet <other>'));
    await tester.pumpAndSettle();
    expect(find.text('Last sync'), findsOneWidget);
    expect(find.text('192.168.1.5:47831'), findsOneWidget);
    await tester.tap(find.text('Forget device'));
    await _confirm(tester, 'Cancel');
    expect(backend.forgotten, isEmpty);
    await tester.tap(find.text('Forget device'));
    await _confirm(tester, 'Forget');
    expect(backend.forgotten, ['tablet']);
    await _reveal(tester, find.text('Technical details'));
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('Port'), findsOneWidget);
    expect(find.text('47831'), findsOneWidget);
    expect(find.text('synthetic-device'), findsOneWidget);
  });

  syncWidgets(
    'disabled sync blocks pairing; busy sync leaves pairing available',
    (tester) async {
      backend.current = syncStatus(enabled: false);
      await controller.refresh();
      await _pump(tester, SyncScreen(controller: controller, store: store));
      FilledButton action(String label) =>
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, label));
      ListTile pairingAction() => tester.widget<ListTile>(
        find.byKey(const ValueKey('sync-add-device')),
      );
      expect(action('Sync now').onPressed, isNull);
      expect(pairingAction().onTap, isNull);
      backend.current = syncStatus();
      await controller.refresh();
      await tester.pump();
      expect(action('Sync now').onPressed, isNotNull);
      expect(pairingAction().onTap, isNotNull);
      backend.syncGate = Completer<void>();
      final running = controller.manual();
      await tester.pump();
      expect(action('Sync now').onPressed, isNull);
      expect(pairingAction().onTap, isNotNull);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNull,
      );
      backend.syncGate!.complete();
      await tester.pump();
      await running;
      await tester.pumpAndSettle();
      expect(action('Sync now').onPressed, isNotNull);
    },
  );

  for (final width in [320.0, 412.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      syncWidgets('status row fits ${width}dp at text scale $scale', (
        tester,
      ) async {
        controller.dispose();
        controller = SyncController(
          backend: backend,
          refreshRecipes: store.refresh,
          isAndroid: true,
          requestPermission: () async => true,
          currentGeneration: () => 0,
        );
        backend.current = syncStatus(
          generation: 0,
          peers: [
            SyncPeer(
              id: 'tablet',
              name: 'Tablet with a comfortably long device name',
              address: '192.0.2.10:47832',
              caughtUp: true,
              lastSync: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            ),
          ],
        );
        await controller.refresh();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1400);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(
          MaterialApp(
            theme: cookdexTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: SyncScreen(controller: controller, store: store),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Synced'), findsOneWidget);
        expect(find.text('1 device · just now'), findsOneWidget);
        expect(find.textContaining('Synced with'), findsNothing);
        final sync = find.byKey(const ValueKey('sync-now'));
        final titleRect = tester.getRect(find.text('Synced'));
        final syncRect = tester.getRect(sync);
        expect(
          syncRect.left > titleRect.right || syncRect.top >= titleRect.bottom,
          isTrue,
        );
        if (width == 320 && scale == 2) {
          expect(syncRect.top, greaterThan(titleRect.bottom));
        }
        expect(syncRect.center.dy, greaterThanOrEqualTo(titleRect.top));
        expect(syncRect.height, greaterThanOrEqualTo(48));
        expect(syncRect.right, closeTo(width - 32, 0.01));
        final add = find.byKey(const ValueKey('sync-add-device'));
        await _reveal(tester, add);
        expect(find.text('Add a device'), findsOneWidget);
        expect(tester.getSize(add).height, greaterThanOrEqualTo(48));
        final pairedCard = find.ancestor(of: add, matching: find.byType(Card));
        expect(
          find.descendant(
            of: pairedCard,
            matching: find.text('Tablet with a comfortably long device name'),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  syncWidgets(
    'offline peers are waiting; actual failures show reason and next action',
    (tester) async {
      const peer = SyncPeer(
        id: 'tablet',
        name: 'Tablet',
        address: '192.168.1.5:47831',
      );
      backend.current = syncStatus(
        peers: [peer],
        reports: const [
          SyncReport(
            id: 'tablet',
            name: 'Tablet',
            status: 'waiting',
            retryAfterSeconds: 60,
          ),
        ],
      );
      await controller.refresh();
      await _pump(tester, SyncScreen(controller: controller, store: store));
      expect(find.text('Needs attention'), findsNothing);
      expect(find.text('Waiting for devices'), findsOneWidget);
      expect(
        find.text('Waiting for device · retrying in 1 min'),
        findsOneWidget,
      );
      expect(find.textContaining('retrying in 1 min'), findsOneWidget);
      backend.current = syncStatus(
        peers: [peer],
        reports: const [
          SyncReport(
            id: 'tablet',
            name: 'Tablet',
            status: 'error',
            error: 'Authentication failed',
          ),
        ],
      );
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Tablet: Authentication failed'), findsOneWidget);
      expect(find.textContaining('pair it again'), findsOneWidget);
    },
  );

  syncWidgets(
    'same-named peer rows and details match stable IDs after rename',
    (tester) async {
      const reports = [
        SyncReport(
          id: 'phone',
          name: 'Android device',
          status: 'waiting',
          retryAfterSeconds: 120,
        ),
        SyncReport(
          id: 'tablet',
          name: 'Android device',
          status: 'error',
          error: 'Tablet authentication failed',
        ),
      ];
      const phone = SyncPeer(
        id: 'phone',
        name: 'Android device',
        address: '192.168.1.5:47831',
      );
      const tablet = SyncPeer(
        id: 'tablet',
        name: 'Android device',
        address: '192.168.1.6:47831',
      );
      backend.current = syncStatus(peers: [phone, tablet], reports: reports);
      await controller.refresh();
      await _pump(tester, SyncScreen(controller: controller, store: store));
      final phoneRow = find.byKey(const ValueKey('sync-peer-phone'));
      final tabletRow = find.byKey(const ValueKey('sync-peer-tablet'));
      expect(
        find.descendant(
          of: phoneRow,
          matching: find.textContaining('Waiting for device'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: phoneRow,
          matching: find.textContaining('Tablet authentication failed'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: tabletRow,
          matching: find.textContaining('Waiting for device'),
        ),
        findsNothing,
      );
      await tester.tap(phoneRow);
      await tester.pumpAndSettle();
      expect(find.text('192.168.1.5:47831'), findsOneWidget);
      expect(find.text('192.168.1.6:47831'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      backend.current = syncStatus(
        peers: const [
          SyncPeer(
            id: 'phone',
            name: 'Kitchen phone',
            address: '192.168.1.5:47831',
          ),
          tablet,
        ],
        reports: reports,
      );
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: phoneRow, matching: find.text('Kitchen phone')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: phoneRow,
          matching: find.textContaining('Waiting for device'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: phoneRow,
          matching: find.textContaining('Tablet authentication failed'),
        ),
        findsNothing,
      );
      await tester.tap(tabletRow);
      await tester.pumpAndSettle();
      expect(find.text('192.168.1.6:47831'), findsOneWidget);
      expect(find.text('192.168.1.5:47831'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  syncWidgets('each Resolve opens only its own recipe conflict', (
    tester,
  ) async {
    repository.conflicts = [
      _conflict(),
      Conflict(
        recipeId: 'bread',
        versions: [
          ConflictVersion(
            id: 'bread-live',
            recipe: recipe('bread', title: 'Bread'),
          ),
          const ConflictVersion(id: 'bread-deleted', deletedAt: '2026-10-02'),
        ],
      ),
    ];
    repository.generation++;
    await store.refresh();
    await _pump(tester, SyncScreen(controller: controller, store: store));
    await tester.tap(find.text('Resolve').last);
    await tester.pumpAndSettle();
    expect(find.text('Bread'), findsOneWidget);
    expect(find.text('Lemon cake'), findsNothing);
    expect(find.text('Keep all'), findsOneWidget);
  });
  void pairingWidgets(
    String description,
    Future<void> Function(WidgetTester) test,
  ) {
    syncWidgets(description, (tester) async {
      try {
        await test(tester);
      } finally {
        // Dispose the invitation countdown inside the fake async test zone.
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  Future<void> joinByPaste(WidgetTester tester) async {
    await tester.tap(find.text('Join a device'));
    await tester.pumpAndSettle();
    if (controller.isAndroid) {
      await tester.tap(find.widgetWithText(TextButton, 'Paste invitation'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> createInvitation(WidgetTester tester) async {
    await tester.tap(find.text('Invite a device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'New invitation'));
    await tester.pumpAndSettle();
  }

  void expectQrPayload(WidgetTester tester, String invitation) {
    final view = tester.widget<PrettyQrView>(find.byType(PrettyQrView));
    final expected = QrImage(
      QrCode.fromData(
        data: invitation,
        errorCorrectLevel: QrErrorCorrectLevel.L,
      ),
    );
    // Public protected member is inspected only to verify the exact encoded payload.
    // ignore: invalid_use_of_protected_member
    expect(view.qrImage.qrModules, expected.qrModules);
    expect(find.text(invitation), findsNothing);
    expect(find.text('Copy invitation'), findsOneWidget);
  }

  pairingWidgets(
    'pairing pauses outgoing exchange until the pasted join finishes',
    (tester) async {
      await _pump(tester, SyncScreen(controller: controller, store: store));
      final add = find.byKey(const ValueKey('sync-add-device'));
      await _reveal(tester, add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(PairingScreen), findsOneWidget);
      expect(backend.pairingCalls, [true]);
      expect(find.byType(TextField), findsNothing);
      await joinByPaste(tester);
      await tester.enterText(
        find.byType(TextField),
        '  recipe-pair:synthetic-input  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
      await tester.pumpAndSettle();
      expect(backend.pairCodes, ['recipe-pair:synthetic-input']);
      expect(find.byType(PairingScreen), findsNothing);
      expect(backend.pairingCalls, [true, false]);
    },
  );

  pairingWidgets('leaving pairing with Back resumes outgoing exchange', (
    tester,
  ) async {
    await _pump(tester, SyncScreen(controller: controller, store: store));
    final add = find.byKey(const ValueKey('sync-add-device'));
    await _reveal(tester, add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite a device'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PairingScreen), findsNothing);
    expect(backend.pairingCalls, [true, false]);
  });

  pairingWidgets(
    'invite and join are separate paths; Android scan is the main join action',
    (tester) async {
      await _pump(tester, PairingScreen(controller: controller));
      expect(find.text('Invite a device'), findsOneWidget);
      expect(find.text('Join a device'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Join a device'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Scan QR code'), findsOneWidget);
      expect(
        find.widgetWithText(TextButton, 'Paste invitation'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text('New invitation'), findsNothing);
      expect(find.textContaining('1. On the other device'), findsOneWidget);
      expect(find.textContaining('2. Choose Invite a device'), findsOneWidget);
      expect(find.textContaining('3. Keep both devices'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Paste invitation'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .decoration!
            .counterText,
        '',
      );
      expect(find.text('0/4096'), findsNothing);
      await tester.tap(find.text('Choose another way'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite a device'));
      await tester.pumpAndSettle();
      expect(find.text('New invitation'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Scan QR code'), findsNothing);
      expect(find.textContaining('2. Choose Join a device'), findsOneWidget);
    },
  );

  pairingWidgets('Windows join offers paste only', (tester) async {
    controller.dispose();
    controller = SyncController(
      backend: backend,
      refreshRecipes: store.refresh,
      isAndroid: false,
      requestPermission: () async => true,
    );
    await controller.refresh();
    await _pump(tester, PairingScreen(controller: controller));
    await tester.tap(find.text('Join a device'));
    await tester.pumpAndSettle();
    expect(find.text('Scan QR code'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.labelText,
      'Paste invitation',
    );
    expect(find.widgetWithText(FilledButton, 'Pair'), findsOneWidget);
    expect(find.text('0/4096'), findsNothing);
  });

  pairingWidgets(
    'invite QR and Copy encode the identical invitation without raw text',
    (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _pump(tester, PairingScreen(controller: controller));
      await createInvitation(tester);
      expectQrPayload(tester, 'recipe-pair:synthetic-secret-1');
      expect(find.textContaining('Expires in 10:'), findsOneWidget);
      await tester.tap(find.text('Copy invitation'));
      await tester.pumpAndSettle();
      expect(copied, 'recipe-pair:synthetic-secret-1');
      expect(backend.invitationAddresses, ['192.168.1.4']);
      expect(find.byType(TextField), findsNothing);
    },
  );

  pairingWidgets('invitation countdown hides QR and Copy at ten minutes', (
    tester,
  ) async {
    var age = Duration.zero;
    await _pump(
      tester,
      PairingScreen(controller: controller, invitationAge: () => age),
    );
    await createInvitation(tester);
    expectQrPayload(tester, 'recipe-pair:synthetic-secret-1');
    expect(find.text('Expires in 10:00'), findsOneWidget);
    age = const Duration(seconds: 19);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Expires in 9:41'), findsOneWidget);
    age = const Duration(minutes: 10);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.text('Copy invitation'), findsNothing);
    expect(find.text('Invitation expired, used or revoked.'), findsOneWidget);
    // Rewinding the test clock cannot restore the discarded local secret.
    age = Duration.zero;
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.text('Copy invitation'), findsNothing);
  });

  pairingWidgets(
    'Add opens at capacity for replacement; missing Wi-Fi explains invitation failure',
    (tester) async {
      backend.current = syncStatus(
        peers: List.generate(
          16,
          (i) => SyncPeer(
            id: 'peer-$i',
            name: 'Peer $i',
            address: '192.0.2.${i + 10}:47832',
          ),
        ),
      );
      await controller.refresh();
      await _pump(tester, SyncScreen(controller: controller, store: store));
      final add = find.byKey(const ValueKey('sync-add-device'));
      await _reveal(tester, add);
      expect(tester.widget<ListTile>(add).onTap, isNotNull);
      expect(tester.widget<ListTile>(add).enabled, isTrue);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(PairingScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      backend.current = syncStatus(addresses: []);
      await controller.refresh();
      await _pump(tester, PairingScreen(controller: controller));
      await createInvitation(tester);
      expect(find.text('Connect to Wi-Fi, then try again.'), findsOneWidget);
      expect(backend.invitationAddresses, isEmpty);
      expect(find.byType(PrettyQrView), findsNothing);
    },
  );

  pairingWidgets(
    'pairing route stays available during exchange; invite waits for it to finish',
    (tester) async {
      await _pump(tester, SyncScreen(controller: controller, store: store));
      backend.syncGate = Completer<void>();
      final running = controller.manual();
      await tester.pump();
      final add = find.byKey(const ValueKey('sync-add-device'));
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PairingScreen), findsOneWidget);
      await tester.tap(find.text('Invite a device'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'New invitation'),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(backend.invitationAddresses, isEmpty);
      backend.syncGate!.complete();
      await tester.pump();
      await running;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'New invitation'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('New invitation'));
      await tester.pumpAndSettle();
      expectQrPayload(tester, 'recipe-pair:synthetic-secret-1');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(backend.pairingCalls, [true, false]);
    },
  );

  pairingWidgets('busy join disables scan and Pair until exchange finishes', (
    tester,
  ) async {
    await _pump(tester, PairingScreen(controller: controller));
    await joinByPaste(tester);
    backend.syncGate = Completer<void>();
    final running = controller.manual();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Scan QR code'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Pair'))
          .onPressed,
      isNull,
    );
    backend.syncGate!.complete();
    await tester.pump();
    await running;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Pair'))
          .onPressed,
      isNotNull,
    );
  });

  for (final id in [null, 'replacement-invitation']) {
    pairingWidgets('backend-invalidated invitation has no QR or Copy ($id)', (
      tester,
    ) async {
      var clipboardWrites = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') clipboardWrites++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _pump(tester, PairingScreen(controller: controller));
      await createInvitation(tester);
      expectQrPayload(tester, 'recipe-pair:synthetic-secret-1');
      backend.current = syncStatus(invitationId: id);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(PrettyQrView), findsNothing);
      expect(find.text('Copy invitation'), findsNothing);
      expect(find.text('Invitation expired, used or revoked.'), findsOneWidget);
      backend.current = syncStatus(invitationId: 'invitation-1');
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(find.byType(PrettyQrView), findsNothing);
      expect(clipboardWrites, 0);
      await tester.tap(find.text('New invitation'));
      await tester.pumpAndSettle();
      expectQrPayload(tester, 'recipe-pair:synthetic-secret-2');
    });
  }

  pairingWidgets('turning sync off invalidates the displayed invitation', (
    tester,
  ) async {
    await _pump(tester, PairingScreen(controller: controller));
    await createInvitation(tester);
    backend.current = syncStatus(enabled: false);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(PrettyQrView), findsNothing);
    expect(find.text('Copy invitation'), findsNothing);
  });

  pairingWidgets(
    'failed status refresh after replacement hides the revoked QR',
    (tester) async {
      await _pump(tester, PairingScreen(controller: controller));
      await createInvitation(tester);
      expectQrPayload(tester, 'recipe-pair:synthetic-secret-1');
      backend.statusError = const ServiceError(
        code: ErrorCode.validation,
        message: 'Local status temporarily unavailable.',
      );
      await tester.tap(find.text('New invitation'));
      await tester.pumpAndSettle();
      expect(backend.invitationAddresses, hasLength(2));
      expect(
        find.text('Local status temporarily unavailable.'),
        findsOneWidget,
      );
      expect(find.byType(PrettyQrView), findsNothing);
      expect(find.text('Copy invitation'), findsNothing);
    },
  );

  pairingWidgets(
    'fresh-invitation error clears the pasted invitation and retains the reason',
    (tester) async {
      backend.pairError = const ServiceError(
        code: ErrorCode.validation,
        message:
            'Pairing could not finish. Create a new invitation and try again.',
      );
      await _pump(tester, PairingScreen(controller: controller));
      await joinByPaste(tester);
      await tester.enterText(find.byType(TextField), 'recipe-pair:expired');
      await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Pairing could not finish. Create a new invitation and try again.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      expect(find.byType(PairingScreen), findsOneWidget);
      expect(controller.busy, isFalse);
    },
  );
  syncWidgets('equal timestamps still produce distinct numbered alternatives', (
    tester,
  ) async {
    repository.conflicts = [
      Conflict(
        recipeId: 'cake',
        versions: [
          ConflictVersion(id: 'phone', recipe: recipe('cake')),
          ConflictVersion(id: 'pc', recipe: recipe('cake')),
          const ConflictVersion(id: 'deleted', deletedAt: '2026-10-02'),
        ],
      ),
    ];
    repository.generation++;
    await store.refresh();
    await _pump(tester, ConflictsScreen(controller: controller, store: store));
    final date = readableSyncTime(
      DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000,
    );
    expect(find.text('Version 1 · $date'), findsOneWidget);
    expect(find.text('Version 2 · $date'), findsOneWidget);
    expect(find.text('Version 3 · Deletion'), findsOneWidget);
    await tester.tap(find.text('Version 2 · $date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use version'));
    await _confirm(tester, 'Use version');
    expect(
      backend.resolutions.single.$2,
      const ConflictChoice.version(id: 'pc'),
    );
  });

  syncWidgets('conflict review contains complete recipes and deletion details', (
    tester,
  ) async {
    repository.conflicts = [_conflict()];
    repository.generation++;
    await store.refresh();
    await _pump(tester, ConflictsScreen(controller: controller, store: store));
    await tester.tap(
      find.text(
        'Version 1 · ${readableSyncTime(DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000)}',
      ),
    );
    await tester.pumpAndSettle();
    final text = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    for (final field in [
      'Lemon cake',
      'soft crumb',
      'Servings: 4',
      'Prep: 10 min',
      'Tags: Quick',
      'Favorite: false',
      '33/100 cup cream [fresh]',
      '1. Mix',
      '2. Bake',
      'overnight',
      'Created: ${readableSyncTime(DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000)}',
      'Revision: 1',
    ]) {
      expect(text, contains(field), reason: field);
    }
    await _reveal(tester, find.text('Version 2 · Deletion'));
    await tester.tap(find.text('Version 2 · Deletion'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Deleted ${readableSyncTime(DateTime(2026, 10, 2).millisecondsSinceEpoch ~/ 1000)}',
      ),
      findsOneWidget,
    );
    expect(find.text('Use deletion'), findsOneWidget);
    expect(find.text('Keep all'), findsOneWidget);
  });

  for (final label in ['Use version', 'Use deletion', 'Keep all']) {
    syncWidgets(
      '$label submits exactly the reviewed conflict after confirmation',
      (tester) async {
        final conflict = _conflict();
        repository.conflicts = [conflict];
        repository.generation++;
        await store.refresh();
        backend.onResolve = (_, _) async {
          repository.conflicts = [];
          repository.generation++;
        };
        await _pump(
          tester,
          ConflictsScreen(controller: controller, store: store),
        );
        if (label != 'Keep all') {
          await tester.tap(
            find.text(
              label == 'Use version'
                  ? 'Version 1 · ${readableSyncTime(DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000)}'
                  : 'Version 2 · Deletion',
            ),
          );
          await tester.pumpAndSettle();
        }
        await _reveal(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(backend.resolutions, isEmpty);
        await _confirm(tester, label);
        expect(backend.resolutions, hasLength(1));
        expect(backend.resolutions.single.$1, same(conflict));
        expect(
          backend.resolutions.single.$2,
          label == 'Keep all'
              ? const ConflictChoice.keepAll()
              : ConflictChoice.version(
                  id: label == 'Use version' ? 'live' : 'deleted',
                ),
        );
        expect(find.text('No unresolved conflicts.'), findsOneWidget);
      },
    );
  }

  syncWidgets('cancel and busy conflict controls cannot discard alternatives', (
    tester,
  ) async {
    repository.conflicts = [_conflict()];
    repository.generation++;
    await store.refresh();
    await _pump(tester, ConflictsScreen(controller: controller, store: store));
    await tester.tap(find.text('Keep all'));
    await _confirm(tester, 'Cancel');
    expect(backend.resolutions, isEmpty);
    await tester.tap(
      find.text(
        'Version 1 · ${readableSyncTime(DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000)}',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Version 2 · Deletion'));
    await tester.pumpAndSettle();
    backend.syncGate = Completer<void>();
    final running = controller.manual();
    await tester.pump();
    for (final label in ['Use version', 'Use deletion', 'Keep all']) {
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
    }
    backend.syncGate!.complete();
    await tester.pump();
    await running;
    await tester.pumpAndSettle();
    expect(backend.resolutions, isEmpty);
  });

  syncWidgets('stale resolution shows error and refreshes versions before retry', (
    tester,
  ) async {
    repository.conflicts = [_conflict()];
    repository.generation++;
    await store.refresh();
    backend.onResolve = (_, _) async {
      repository.conflicts = [_conflict(liveId: 'new-live', revision: 2)];
      repository.generation++;
      throw const ServiceError(
        code: ErrorCode.conflictChanged,
        message: 'Conflict changed. Review the current versions before choosing again.',
      );
    };
    await _pump(tester, ConflictsScreen(controller: controller, store: store));
    await tester.tap(find.text('Keep all'));
    await _confirm(tester, 'Keep all');
    expect(
      find.text(
        'Conflict changed. Review the current versions before choosing again.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Version 1 · ${readableSyncTime(DateTime(2026, 1, 1).millisecondsSinceEpoch ~/ 1000)}',
      ),
      findsNothing,
    );
    expect(
      find.text(
        'Version 1 · ${readableSyncTime(DateTime(2026, 1, 2).millisecondsSinceEpoch ~/ 1000)}',
      ),
      findsOneWidget,
    );
    backend.onResolve = (_, _) async {};
    await tester.tap(find.text('Keep all'));
    await _confirm(tester, 'Keep all');
    expect(backend.resolutions.last.$1.versions.map((v) => v.id), [
      'new-live',
      'deleted',
    ]);
    expect(controller.error, isNull);
    expect(tester.takeException(), isNull);
  });
}
