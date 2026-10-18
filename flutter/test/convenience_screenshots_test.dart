import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_scaling_test.dart' show ScalingFake;
import 'import_photo_save_test.dart' show ArchivePlatform, ArchiveService;

void main() {
  testWidgets('convenience features real-font layouts', (tester) async {
    if (Platform.environment['CONVENIENCE_SCREENSHOTS'] != '1') return;
    final sdk = Platform.environment['FLUTTER_SDK']!;
    await tester.runAsync(() async {
      final font = FontLoader('Roboto');
      for (final weight in ['regular', 'bold']) {
        font.addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await font.load();
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
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final config in [
      ('small', const Size(320, 800), 1.0),
      ('normal', const Size(412, 892), 1.0),
      ('largest', const Size(412, 892), 2.0),
      ('tablet', const Size(1280, 800), 1.0),
    ]) {
      tester.view.physicalSize = config.$2;
      Future<void> mount(Widget screen) async {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: cookdexTheme(largerBody: config.$2.width >= 600)
                  .copyWith(platform: TargetPlatform.android),
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
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/convenience/screens/${config.$1}-$state.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final repo = ScalingFake();
      repo.recipes['scale']!.fields.steps
        ..clear()
        ..addAll([
          'Toast farofa: Add 3 tablespoons of butter and stir gently until golden.',
          'Serve: Spoon over the rice.',
        ]);
      final prefs = LocalPreferences.memory();
      final store = RecipeStore(repo, prefs);
      await store.refresh();
      final cook = CookController(preferences: prefs, setWake: (_) async {});
      await mount(
        Scaffold(
          body: RecipeTextScale(
            factor: config.$3 == 2 ? 1.3 : 1,
            child: Builder(
              builder: (context) => RecipeDetail(
                store: store,
                recipeId: 'scale',
                cook: cook,
                onBack: () {},
                onActions: () {},
                onEdit: () {},
                onSource: (_) async {},
                onAddToShopping: () => showShoppingSelection(
                  context,
                  store,
                  repo.recipes['scale']!,
                  scale: cook.scale,
                ),
              ),
            ),
          ),
        ),
      );
      await capture('recipe-1x');
      await tester.tap(find.byKey(const Key('recipe-scale-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('recipe-scale-4')));
      await tester.pumpAndSettle();
      await capture('recipe-2x');
      await tester.tap(find.byKey(const Key('cook-toggle')));
      await tester.pumpAndSettle();
      if (config.$1 == 'largest') {
        await tester.ensureVisible(find.text('Steps'));
        await tester.pumpAndSettle();
      }
      await capture('cook-2x');
      if (config.$1 == 'small' || config.$1 == 'normal') {
        await tester.ensureVisible(find.text('Add to shopping list'));
        await tester.tap(find.text('Add to shopping list'));
        await tester.pumpAndSettle();
        await capture('shopping-selection');
      }
      await tester.pumpWidget(const SizedBox());
      cook.dispose();
      store.dispose();
      prefs.dispose();
      if (config.$1 == 'tablet') continue;
      final c = ImportController(
        service: ArchiveService(ArchivePlatform()),
        storage: MemoryDraftStorage(),
      );
      c.tab = ImportTab.photos;
      await mount(ImportScreen(controller: c, onReview: (_, _) async => null));
      await tester.ensureVisible(find.text('Save photos to device'));
      await tester.pumpAndSettle();
      await capture('photos-off');
      await tester.tap(find.text('Save photos to device'));
      await tester.pumpAndSettle();
      await capture('photos-on');
      expect(c.savePhotosToDevice, isTrue);
      await tester.pumpWidget(const SizedBox());
      await c.flush();
      c.dispose();
    }
  });
}
