import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/ui/snapshots_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'snapshots_screen_test.dart'
    show snapshotFixture, snapshotSettingsFixture;

void main() {
  testWidgets('snapshot real-font screenshot matrix', (tester) async {
    if (Platform.environment['SNAPSHOTS_SCREENSHOTS'] != '1') return;
    final sdk = Platform.environment['FLUTTER_SDK']!;
    await tester.runAsync(() async {
      final roboto = FontLoader('Roboto');
      for (final weight in ['regular', 'bold']) {
        roboto.addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await roboto.load();
      for (final family in [
        'MaterialSymbolsRounded',
        'MaterialSymbolsOutlined',
      ]) {
        final symbols = FontLoader('packages/material_symbols_icons/$family');
        symbols.addFont(
          rootBundle.load(
            'packages/material_symbols_icons/lib/fonts/$family.ttf',
          ),
        );
        await symbols.load();
      }
    });
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final config in [
      ('small', const Size(320, 800), 1.0),
      ('normal', const Size(412, 892), 1.0),
      ('largest', const Size(412, 892), 2.0),
      ('tablet-landscape', const Size(1280, 800), 1.0),
      ('desktop', const Size(1440, 900), 1.0),
    ]) {
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      Future<void> mount(Widget screen) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('snapshots-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: cookdexTheme(largerBody: config.$2.width >= 600).copyWith(
                platform: config.$1 == 'desktop'
                    ? TargetPlatform.windows
                    : TargetPlatform.android,
              ),
              // Recipe text scale is Extra large below; these Settings routes
              // correctly use only system scaling, like the rest of Settings.
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$3)),
                child: child!,
              ),
              home: screen,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String state) async {
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('snapshots-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/snapshots/screens/${config.$1}-$state.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      SnapshotsScreen screen(Future<SnapshotListing> Function() load) =>
          SnapshotsScreen(
            load: load,
            onRestore: (_) async {},
            onExport: (_) async {},
          );
      await mount(
        screen(
          () async => SnapshotListing(
            entries: [
              snapshotFixture,
              LocalSnapshotEntry(
                id: 'second',
                createdAt: DateTime(2026, 10, 15, 18, 5),
                recipeCount: 24,
                omittedCount: 0,
                reason: 'automatic',
              ),
            ],
          ),
        ),
      );
      if (config.$1 == 'largest') await capture('list-top');
      // Show the complete first entry and its action wrapping at large text.
      await tester.ensureVisible(find.text('Export ZIP').first);
      await tester.pumpAndSettle();
      await capture('list');
      await mount(
        screen(
          () async =>
              const SnapshotListing(entries: [], repeatedlyFailing: true),
        ),
      );
      await capture('repeated-failure');
      await mount(screen(() async => const SnapshotListing(entries: [])));
      await capture('empty');
      await mount(screen(() async => throw StateError('synthetic')));
      await capture('failure');
      await mount(
        snapshotSettingsFixture(
          failing: true,
          recipeTextScale: config.$3 == 2 ? 1.3 : 1,
        ),
      );
      await tester.scrollUntilVisible(find.text('Snapshots'), 200);
      await Scrollable.ensureVisible(
        tester.element(
          find
              .ancestor(
                of: find.text('Snapshots'),
                matching: find.byType(ListTile),
              )
              .first,
        ),
        alignment: 0.3,
      );
      await tester.pumpAndSettle();
      await capture('settings');
      await mount(
        snapshotSettingsFixture(recipeTextScale: config.$3 == 2 ? 1.3 : 1),
      );
      await tester.scrollUntilVisible(find.text('Snapshots'), 200);
      await Scrollable.ensureVisible(
        tester.element(
          find
              .ancestor(
                of: find.text('Snapshots'),
                matching: find.byType(ListTile),
              )
              .first,
        ),
        alignment: 0.3,
      );
      await tester.pumpAndSettle();
      await capture('settings-healthy');
    }
  });
}
