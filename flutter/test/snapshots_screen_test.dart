import 'dart:async';

import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/ui/snapshots_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final snapshotFixture = LocalSnapshotEntry(
  id: 'synthetic-snapshot',
  createdAt: DateTime(2026, 10, 16, 9, 30),
  recipeCount: 24,
  omittedCount: 2,
  reason: 'before_restore',
);

SettingsScreen snapshotSettingsFixture({
  bool failing = false,
  VoidCallback? onSnapshots,
  double recipeTextScale = 1,
}) => SettingsScreen(
  hasPrevious: false,
  syncSummary: 'Sync is off',
  onSnapshots: onSnapshots ?? () {},
  snapshotsFailing: failing,
  shoppingKeepAwake: false,
  onShoppingKeepAwake: (_) {},
  recipeTextScale: recipeTextScale,
  onRecipeTextScale: (_) {},
  isAndroid: true,
  wallpaperColors: false,
  onWallpaperColors: (_) {},
  version: 'Test fixture',
);

void main() {
  Future<void> mount(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(MaterialApp(theme: cookdexTheme(), home: screen));
    await tester.pumpAndSettle();
  }

  testWidgets('snapshot load failure retries into empty state', (tester) async {
    var calls = 0;
    await mount(
      tester,
      SnapshotsScreen(
        load: () async {
          if (++calls == 1) throw StateError('synthetic');
          return const SnapshotListing(entries: []);
        },
        onRestore: (_) async {},
        onExport: (_) async {},
      ),
    );
    expect(find.text('Could not load snapshots.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No snapshots yet.'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets(
    'restore awaits confirmation callback and refreshes; export does not',
    (tester) async {
      var loads = 0;
      var exports = 0;
      final restore = Completer<void>();
      await mount(
        tester,
        SnapshotsScreen(
          load: () async {
            loads++;
            return SnapshotListing(entries: [snapshotFixture]);
          },
          onRestore: (entry) {
            expect(entry.id, snapshotFixture.id);
            return restore.future;
          },
          onExport: (_) async {
            exports++;
          },
        ),
      );
      expect(
        find.textContaining('24 recipes · Before restore'),
        findsOneWidget,
      );
      expect(find.textContaining('2 recipes were omitted'), findsOneWidget);
      await tester.tap(find.text('Export ZIP'));
      await tester.pumpAndSettle();
      expect(exports, 1);
      expect(loads, 1);
      await tester.tap(find.text('Restore'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Export ZIP'))
            .onPressed,
        isNull,
      );
      expect(loads, 1);
      restore.complete();
      await tester.pumpAndSettle();
      expect(loads, 2);
    },
  );

  testWidgets('export failure is inline and retry remains enabled', (
    tester,
  ) async {
    await mount(
      tester,
      SnapshotsScreen(
        load: () async => SnapshotListing(
          entries: [snapshotFixture],
          repeatedlyFailing: true,
        ),
        onRestore: (_) async {},
        onExport: (_) async => throw StateError('private diagnostic'),
      ),
    );
    await tester.tap(find.text('Export ZIP'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not export this snapshot. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private diagnostic'), findsNothing);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Export ZIP'))
          .onPressed,
      isNotNull,
    );
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Settings shows quiet snapshot status and opens callback', (
    tester,
  ) async {
    var opened = false;
    await mount(
      tester,
      snapshotSettingsFixture(failing: true, onSnapshots: () => opened = true),
    );
    await tester.scrollUntilVisible(find.text('Snapshots'), 200);
    expect(
      find.text('Automatic snapshots have not been saving'),
      findsOneWidget,
    );
    await tester.tap(find.text('Snapshots'));
    expect(opened, isTrue);
    expect(find.byType(SnackBar), findsNothing);
  });
}
