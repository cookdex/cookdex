import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository;
import 'sync_controller_test.dart' show FakeSyncBackend, syncStatus;

void main() {
  testWidgets('C9 sync settings before and after screenshots', (tester) async {
    final ranges = Platform.environment['A1_SCREENSHOTS'] == '1';
    if (!ranges && Platform.environment['C9_POLISH_SCREENSHOTS'] != '1') return;
    final phase = Platform.environment['C9_POLISH_PHASE'] ?? 'after';
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
      final material = FontLoader('MaterialIcons');
      material.addFont(
        File(
          '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await material.load();
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
    for (final entry
        in (ranges
                ? {
                    'small': const Size(360, 800),
                    'normal': const Size(412, 892),
                    'largest': const Size(412, 892),
                    'tablet-landscape': const Size(1280, 800),
                  }
                : {
                    'phone': const Size(390, 844),
                    'tablet': const Size(800, 1280),
                    'windows': const Size(1280, 900),
                  })
            .entries) {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      final prefs = LocalPreferences.memory();
      final store = RecipeStore(FakeRepository([]), prefs);
      await store.initialize();
      final backend = FakeSyncBackend();
      backend.current = syncStatus(
        reports: ranges
            ? const [
                SyncReport(
                  id: 'tablet',
                  name: 'Pixel Tablet',
                  status: 'error',
                  error: 'Incompatible LAN sync version. Update all cookdex devices, then retry.',
                ),
              ]
            : const [],
        peers: [
          SyncPeer(
            id: 'tablet',
            name: 'Pixel Tablet',
            address: '192.168.1.5:47832',
            lastSync: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
          ),
          const SyncPeer(
            id: 'pc',
            name: 'SYLPH-PC',
            address: '192.168.1.6:47832',
          ),
        ],
      );
      final controller = SyncController(
        backend: backend,
        refreshRecipes: store.refresh,
        isAndroid: entry.key != 'windows',
        requestPermission: () async => true,
      );
      await controller.refresh();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(entry.key == 'largest' ? 2 : 1),
              ),
              child: child!,
            ),
            home: SyncScreen(controller: controller, store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> shot(String name) async {
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '${ranges ? '../artifacts/a1-ranges/screens' : '../artifacts/c9-polish/screens'}/$phase-${entry.key}-$name.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shot('sync-top');
      await tester.drag(
        find.byWidgetPredicate((w) => w is ListView).first,
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      await shot('sync-lower');
      if (ranges) {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        store.dispose();
        prefs.dispose();
        continue;
      }
      if (phase == 'after') {
        await tester.drag(
          find.byWidgetPredicate((w) => w is ListView).first,
          const Offset(0, 1000),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Pixel Tablet'), 300);
        await tester.tap(find.text('Pixel Tablet'));
        await tester.pumpAndSettle();
        await shot('device-details');
        await tester.pageBack();
        await tester.pumpAndSettle();
        backend.current = syncStatus(
          peers: backend.current.peers,
          reports: const [
            SyncReport(
              id: 'pc',
              name: 'SYLPH-PC',
              status: 'error',
              error: 'Connection rejected. Pairing trust did not match.',
            ),
          ],
        );
        await controller.refresh();
        await tester.drag(
          find.byWidgetPredicate((w) => w is ListView).first,
          const Offset(0, 1000),
        );
        await tester.pumpAndSettle();
        await shot('sync-attention');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      store.dispose();
      prefs.dispose();
    }
  });
}
