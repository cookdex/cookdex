import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:cookdex/help_content.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/pairing_screen.dart';
import 'package:cookdex/ui/scan_invitation_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_scanner_camera.dart';
import 'sync_controller_test.dart' show FakeSyncBackend;

void main() {
  testWidgets('F4 scanner and help screenshot matrix', (tester) async {
    if (Platform.environment['F4_SCREENSHOTS'] != '1') return;
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
      final materialIcons = FontLoader('MaterialIcons');
      materialIcons.addFont(
        File(
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
      await materialIcons.load();
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
    final original = CameraPlatform.instance;
    addTearDown(() => CameraPlatform.instance = original);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final config in [
      ('small', const Size(320, 800), 1.0),
      ('normal', const Size(412, 892), 1.0),
      ('largest', const Size(412, 892), 2.0),
      ('tablet-landscape', const Size(1280, 800), 1.0),
    ]) {
      final preferences = LocalPreferences.memory();
      if (config.$3 == 2) {
        preferences.setRecipeTextSize(RecipeTextSize.extraLarge);
      }
      // Settings/help/scanner routes intentionally do not use recipe text size.
      final controller = SyncController(
        backend: FakeSyncBackend(),
        refreshRecipes: () async {},
        isAndroid: true,
        requestPermission: () async => true,
      );
      await controller.lifecycle(true);
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      final camera = FakeScannerCamera();
      CameraPlatform.instance = camera;
      Future<void> mount(Widget screen) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('f4-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$3)),
                child: child!,
              ),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(builder: (_) => screen),
                    ),
                    child: const Text('Open fixture'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open fixture'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
      }

      Future<void> reveal(Finder finder) async {
        if (finder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(finder, 250);
        } else {
          await tester.ensureVisible(finder);
        }
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('f4-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('../artifacts/f4/screens/${config.$1}-$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await mount(const ScanInvitationScreen());
      expect(find.byKey(const Key('synthetic-camera-preview')), findsOneWidget);
      await capture('scanner-ready-synthetic-preview');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
      camera.unavailable = true;
      await mount(const ScanInvitationScreen());
      expect(
        find.textContaining('Camera access is unavailable.'),
        findsOneWidget,
      );
      await capture('scanner-unavailable');
      await mount(PairingScreen(controller: controller));
      await tester.tap(find.text('Join a device'));
      await tester.pumpAndSettle();
      await reveal(find.text('Paste invitation'));
      await tester.tap(find.text('Paste invitation'));
      await tester.pumpAndSettle();
      await reveal(find.widgetWithText(FilledButton, 'Pair'));
      await capture('join-paste');
      await mount(
        HowCookdexWorksScreen(
          loadAppInfo: () async => 'Synthetic fixture',
          openUrl: (_) async {},
        ),
      );
      await tester.tap(find.text('Start here'));
      await tester.pumpAndSettle();
      await reveal(find.text('Sync'));
      await tester.tap(find.text('Sync'));
      await tester.pumpAndSettle();
      final paragraphs = helpSections
          .singleWhere((section) => section.id == 'sync')
          .paragraphs;
      for (var i = 0; i < paragraphs.length; i++) {
        if (paragraphs[i].toLowerCase().contains('camera') ||
            paragraphs[i].toLowerCase().contains('qr')) {
          await reveal(find.text(paragraphs[i]));
          await capture('help-scanner-$i');
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
      controller.dispose();
      preferences.dispose();
    }
  });
}
