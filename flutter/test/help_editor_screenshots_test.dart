import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/help_content.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('updated editor help screenshot matrix', (tester) async {
    final ranges = Platform.environment['A1_SCREENSHOTS'] == '1';
    if (!ranges && Platform.environment['APP_PERF_SCREENSHOTS'] != '1') return;
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
    final paragraphs = helpSections
        .singleWhere((s) => s.id == 'adding')
        .paragraphs;
    final paragraph = paragraphs[ranges ? 1 : 0];
    expect(paragraph, contains(ranges ? 'ranges' : 'Choose Write a recipe'));
    for (final config in [
      ('small', const Size(360, 800), 1.0),
      ('normal', const Size(412, 892), 1.0),
      ('largest', const Size(412, 892), 2.0),
      ('tablet-landscape', const Size(1280, 800), 1.0),
    ]) {
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('help-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(config.$3)),
              // Help is opened on the root navigator without RecipeTextScale;
              // Extra large recipe text does not enlarge this real screen.
              child: child!,
            ),
            home: HowCookdexWorksScreen(
              loadAppInfo: () async => 'Synthetic screenshot fixture',
              openUrl: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Getting started'));
      await tester.pumpAndSettle();
      final heading = find.text('Adding and editing recipes');
      await tester.ensureVisible(heading);
      await tester.pumpAndSettle();
      await tester.tap(heading);
      await tester.pumpAndSettle();
      final copy = find.byKey(ValueKey('help-paragraph-$paragraph'));
      await tester.ensureVisible(copy);
      await tester.pumpAndSettle();
      final bodyRect = tester.getRect(
        find.ancestor(of: copy, matching: find.byType(SafeArea)).first,
      );
      final copyRect = tester.getRect(copy);
      expect(copyRect.top, greaterThanOrEqualTo(bodyRect.top));
      expect(copyRect.bottom, lessThanOrEqualTo(bodyRect.bottom));
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('help-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '${ranges ? '../artifacts/a1-ranges/screens/' : '../artifacts/c9-app-performance/help-screens/'}'
          '${config.$1}-adding-recipes.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
