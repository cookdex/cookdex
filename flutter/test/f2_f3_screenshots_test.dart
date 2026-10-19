import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/help_content.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository;
import 'sync_controller_test.dart' show FakeSyncBackend, syncStatus;

void main() {
  testWidgets('F2 F3 real sync pairing and help screenshot matrix', (
    tester,
  ) async {
    if (Platform.environment['F2_F3_SCREENSHOTS'] != '1') return;
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
    ]) {
      final preferences = LocalPreferences.memory();
      if (config.$3 == 2) {
        preferences.setRecipeTextSize(RecipeTextSize.extraLarge);
      }
      final store = RecipeStore(FakeRepository([]), preferences);
      await store.initialize();
      final backend = FakeSyncBackend();
      final controller = SyncController(
        backend: backend,
        refreshRecipes: store.refresh,
        isAndroid: true,
        requestPermission: () async => true,
      );
      await controller.lifecycle(true);
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      Future<void> mount(Widget screen) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('f2-f3-capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
              // These settings routes intentionally do not apply recipe text size.
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
          find.byKey(const Key('f2-f3-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/f2-f3/screens/${config.$1}-$name.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      backend.current = syncStatus(rePairRequired: true);
      await controller.refresh();
      await mount(SyncScreen(controller: controller, store: store));
      await capture('notice');
      backend.current = syncStatus(
        peers: const [
          SyncPeer(
            id: 'unfinished',
            name: 'Kitchen tablet',
            address: '<lan-address>',
            pairingPending: true,
          ),
        ],
      );
      await controller.refresh();
      await mount(SyncScreen(controller: controller, store: store));
      await reveal(find.text('Kitchen tablet'));
      await capture('unfinished-pairing');
      await tester.tap(find.text('Kitchen tablet'));
      await tester.pumpAndSettle();
      await reveal(find.text('Forget setup'));
      await tester.tap(find.text('Forget setup'));
      await tester.pumpAndSettle();
      await capture('forget-setup-dialog');
      backend.current = syncStatus();
      await controller.refresh();
      await mount(PairingScreen(controller: controller));
      await tester.tap(find.text('Invite a device'));
      await tester.pumpAndSettle();
      await reveal(find.text('New invitation'));
      await tester.tap(find.text('New invitation'));
      await tester.pumpAndSettle();
      await reveal(find.text('Copy invitation'));
      await capture('invite-valid');
      backend.current = syncStatus();
      await controller.refresh();
      await tester.pumpAndSettle();
      await capture('invite-consumed');
      await mount(PairingScreen(controller: controller));
      await tester.tap(find.text('Join a device'));
      await tester.pumpAndSettle();
      await reveal(find.widgetWithText(TextButton, 'Paste invitation'));
      await tester.tap(find.widgetWithText(TextButton, 'Paste invitation'));
      await tester.pumpAndSettle();
      await reveal(find.widgetWithText(FilledButton, 'Pair'));
      await capture('join-paste');
      backend.pairError = const ServiceError(
        code: ErrorCode.validation,
        message: 'Update cookdex on the other device to keep syncing.',
      );
      await tester.enterText(
        find.byType(TextField),
        'recipe-pair:synthetic-invitation',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await reveal(find.widgetWithText(FilledButton, 'Pair'));
      await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
      await tester.pumpAndSettle();
      await reveal(find.text(controller.error!));
      await capture('join-update');
      await mount(
        HowCookdexWorksScreen(
          loadAppInfo: () async => 'Synthetic fixture',
          openUrl: (_) async {},
        ),
      );
      await tester.tap(find.text('Getting started'));
      await tester.pumpAndSettle();
      await reveal(find.text('Syncing your devices'));
      await tester.tap(find.text('Syncing your devices'));
      await tester.pumpAndSettle();
      final paragraphs = helpSections
          .singleWhere((section) => section.id == 'sync')
          .paragraphs;
      await reveal(find.byKey(ValueKey('help-paragraph-${paragraphs[1]}')));
      await capture('help-invitations');
      await reveal(find.byKey(ValueKey('help-paragraph-${paragraphs[3]}')));
      await capture('help-repair-sync');
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      store.dispose();
      preferences.dispose();
    }
  });
}
