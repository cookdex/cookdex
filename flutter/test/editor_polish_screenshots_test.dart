import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, reveal;

void main() {
  testWidgets('editor polish rendered matrix', (tester) async {
    final sdk = Platform.environment['FLUTTER_SDK']!;
    await tester.runAsync(() async {
      final font = FontLoader('Roboto');
      for (final weight in ['regular', 'medium', 'bold']) {
        font.addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await font.load();
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

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetViewInsets);
    final manifest = <String>[];
    for (final dark in [false, true]) {
      for (final config in [
        ('small-phone', const Size(320, 800), 1.0),
        ('normal-phone', const Size(390, 844), 1.0),
        ('largest-phone', const Size(390, 844), 2.0),
        ('tablet-landscape', const Size(1280, 800), 1.0),
      ]) {
        tester.view.physicalSize = config.$2;
        tester.view.viewInsets = const FakeViewPadding();
        final (c, _, store) = await controller();
        if (config.$3 == 2.0) {
          store.preferences.setRecipeTextSize(RecipeTextSize.extraLarge);
        }
        c.draft.title = 'Golden tortillas';
        c.draft.description = 'Soft tortillas for a simple family supper.';
        c.draft.servings = '';
        c.draft.prepTime = '15 min';
        c.draft.cookTime = '20 min';
        c.draft.totalTime = '35 min';
        final row = c.draft.sections.first.rows.first;
        row.amount = '1 1/2';
        row.unit = 'cups';
        row.name = 'flour';
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: MaterialApp(
              theme: cookdexTheme(
                colors: dark ? cookdexColors : cookdexLightColors,
              ).copyWith(platform: TargetPlatform.android),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$3)),
                child: child!,
              ),
              home: RecipeEditor(controller: c),
            ),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> capture(String state) async {
          await tester.pumpAndSettle();
          final name = '${dark ? 'dark' : 'light'}-${config.$1}-$state.png';
          expect(tester.takeException(), isNull, reason: name);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('../artifacts/editor-polish/screens/$name');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          manifest.add(name);
        }

        await reveal(tester, find.byKey(const ValueKey('field-servings')));
        await capture('metadata');
        final amount = find.byKey(ValueKey('${row.id}-amount'));
        await reveal(tester, amount);
        await capture('ingredient-resting');
        await tester.tap(amount);
        tester.view.viewInsets = const FakeViewPadding(bottom: 240);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(amount), alignment: .3);
        await capture('amount-active');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    }
    expect(manifest.length, 24);
    await tester.runAsync(
      () =>
          File('../artifacts/editor-polish/screens/manifest.txt')
              .writeAsString('${manifest.join('\n')}\n'),
    );
  }, skip: Platform.environment['EDITOR_POLISH_SCREENSHOTS'] != '1');
}
