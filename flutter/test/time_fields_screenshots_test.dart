import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show reveal;
import 'time_fields_test.dart' show timeConfigurations, timeController, timeBox;

void main() {
  testWidgets('time fields rendered matrix', (tester) async {
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
    final manifest = <String>[];
    for (final dark in [false, true]) {
      for (final config in timeConfigurations) {
        for (final imported in [false, true]) {
          for (final filled in [false, true]) {
            tester.view.physicalSize = config.$2;
            final (c, store) = await timeController(
              imported: imported,
              filled: filled,
            );
            if (config.$3 == 2) {
              store.preferences.setRecipeTextSize(RecipeTextSize.extraLarge);
            }
            await tester.pumpWidget(
              RepaintBoundary(
                key: const Key('capture'),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
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
            expect(
              find.text('Review import'),
              imported ? findsOneWidget : findsNothing,
            );
            final group = find.byKey(const ValueKey('recipe-times'));
            await reveal(tester, group);
            await Scrollable.ensureVisible(
              tester.element(group),
              alignment: .3,
            );
            await tester.pumpAndSettle();
            final name =
                '${dark ? 'dark' : 'light'}-${config.$1}-${imported ? 'review-import' : 'editor'}-${filled ? 'filled' : 'empty'}.png';
            expect(tester.takeException(), isNull, reason: name);
            for (final key in ['prep', 'cook', 'total']) {
              final rect = tester.getRect(timeBox(key));
              expect(
                rect.top,
                greaterThan(80),
                reason: '$name: label below app bar',
              );
              expect(
                rect.bottom,
                lessThan(config.$2.height - 60),
                reason: '$name: complete field visible',
              );
            }
            if (imported) {
              final attribution = tester.getRect(
                find.text('Total time: AI guess'),
              );
              expect(
                attribution.bottom,
                lessThan(config.$2.height - 60),
                reason: name,
              );
            }
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File('../artifacts/time-fields/screens/$name');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
            manifest.add(name);
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
          }
        }
      }
    }
    expect(manifest.length, 32);
    await tester.runAsync(
      () =>
          File('../artifacts/time-fields/screens/manifest.txt')
              .writeAsString('${manifest.join('\n')}\n'),
    );
  }, skip: Platform.environment['TIME_FIELDS_SCREENSHOTS'] != '1');
}
