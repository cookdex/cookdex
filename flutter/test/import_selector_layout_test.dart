import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakeService;

void main() {
  testWidgets('Smart Import selector fits narrow and enlarged text', (
    tester,
  ) async {
    final phase = Platform.environment['IMPORT_LAYOUT_CAPTURE'];
    if (phase != null) {
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
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final config in [
      ('small', const Size(320, 800), 1.0),
      ('normal', const Size(412, 892), 1.0),
      ('largest', const Size(412, 892), 2.0),
      ('tablet-landscape', const Size(1280, 800), 1.0),
      ('small-largest', const Size(320, 800), 2.0),
    ]) {
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      final controller = ImportController(
        service: ImportFakeService(),
        storage: MemoryDraftStorage(),
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(config.$3)),
              child: child!,
            ),
            home: ImportScreen(
              controller: controller,
              onReview: (_, _) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      if (phase != 'before') {
        for (final label in ['Text', 'Link', 'Photos']) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(label),
          );
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length),
          );
          expect(
            boxes.map((box) => box.top).toSet(),
            hasLength(1),
            reason: '${config.$1}: $label must stay on one line',
          );
        }
        final selector = tester.widget<SegmentedButton<ImportTab>>(
          find.byType(SegmentedButton<ImportTab>),
        );
        expect(selector.selected, {ImportTab.photos});
        controller.busy = true;
        controller.changed();
        await tester.pump();
        expect(
          tester
              .widget<SegmentedButton<ImportTab>>(
                find.byType(SegmentedButton<ImportTab>),
              )
              .onSelectionChanged,
          isNull,
        );
        controller.busy = false;
        controller.changed();
        await tester.pumpAndSettle();
      }
      if (phase != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/performance-polish/import-layout/$phase/${config.$1}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
