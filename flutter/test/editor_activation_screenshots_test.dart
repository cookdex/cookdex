import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/editor_model.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, reveal;

void main() {
  testWidgets('editor activation before and after screenshot matrix', (
    tester,
  ) async {
    final ranges = Platform.environment['A1_SCREENSHOTS'] == '1';
    if (!ranges && Platform.environment['APP_PERF_SCREENSHOTS'] != '1') return;
    final phase = Platform.environment['APP_PERF_PHASE'] ?? 'after';
    expect(phase, isIn(['before', 'after']));
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
    addTearDown(tester.view.resetViewInsets);
    for (final config in [
      ('small', const Size(320, 800), 1.0, 1.0),
      ('normal', const Size(412, 892), 1.0, 1.0),
      ('largest', const Size(412, 892), 2.0, 1.3),
      ('tablet-landscape', const Size(1280, 800), 1.0, 1.0),
    ]) {
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      tester.view.resetViewInsets();
      final (c, _, _) = await controller();
      c.draft.title = 'Roasted vegetables and lentils';
      final first = EditableIngredient(
        amount: ranges ? '1/2–1 1/2' : '1 1/2',
        unit: 'cups',
        name: 'Cooked green lentils, drained and rinsed thoroughly',
        prepNote:
            'Rinse under cold water, then leave to drain for five minutes.',
        showNote: true,
      );
      final focusRow = EditableIngredient(
        amount: ranges ? '2–3' : '2',
        unit: 'tbsp',
        name: 'Olive',
      );
      c.draft.sections.first.rows
        ..clear()
        ..addAll([
          first,
          focusRow,
          EditableIngredient(name: 'Carrots, cut into small even pieces'),
          EditableIngredient(),
        ]);
      final step = EditableStep(
        'Heat the oven to 200°C. Spread the carrots on a large tray.\n'
        'Toss with olive oil and roast until tender, turning halfway through.',
      );
      c.draft.steps
        ..clear()
        ..addAll([
          step,
          EditableStep(
            'Fold the vegetables into the lentils. Taste and season '
            'before serving warm with fresh herbs.',
          ),
        ]);
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('editor-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(config.$3)),
              child: RecipeTextScale(factor: config.$4, child: child!),
            ),
            home: RecipeEditor(
              controller: c,
              ingredientSuggestions: const [
                'Olive oil',
                'Olives',
                'Olive paste',
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      Future<void> shot(String name) async {
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('editor-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final evidence = Platform.environment['APP_PERF_EVIDENCE_DIR'] ??
              (ranges ? '../artifacts/a1-ranges/screens/' : '../artifacts/c9-app-performance/screens/');
          final file = File(
            '$evidence/'
            '$phase-${config.$1}-editor-$name.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      if (!ranges) {
        await reveal(tester, find.byKey(const ValueKey('field-servings')));
        await shot('empty-metadata');
      }
      await reveal(tester, find.byKey(ValueKey('${first.id}-name')));
      await shot('ingredients');
      final focused = find.byKey(
        ValueKey('${focusRow.id}-${ranges ? 'amount' : 'name'}'),
      );
      await reveal(tester, focused);
      await tester.tap(focused);
      // A synthetic IME inset exercises Android's suggestion visibility and
      // available editing viewport. The OS keyboard itself is not rendered.
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      await reveal(tester, focused);
      if (!ranges) {
        expect(
          find.byKey(const ValueKey('editor-suggestion-strip')),
          findsOneWidget,
        );
      }
      await shot(ranges ? 'focused-range' : 'focused-suggestions');
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      if (ranges) {
        await tester.pumpWidget(const SizedBox.shrink());
        continue;
      }
      final stepField = find.byKey(ValueKey('${step.id}-text'));
      await reveal(tester, stepField);
      await tester.tap(stepField);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete step 1'), findsOneWidget);
      await shot('multiline-step-editing');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
