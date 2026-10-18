import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/editor_model.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show controller, reveal;

Future<void> _fonts(WidgetTester tester) async {
  final sdk =
      Platform.environment['FLUTTER_SDK'] ??
      (throw StateError('Set FLUTTER_SDK before running font tests'));
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
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
    await icons.load();
    for (final family in [
      'MaterialSymbolsRounded',
      'MaterialSymbolsOutlined',
    ]) {
      final loader = FontLoader('packages/material_symbols_icons/$family');
      loader.addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/$family.ttf',
        ),
      );
      await loader.load();
    }
  });
}

void main() {
  for (final dark in [false, true]) {
    for (final config in [
      ('small', const Size(320, 800), 1.0),
      ('normal', const Size(390, 844), 1.0),
      ('largest', const Size(390, 844), 2.0),
      ('small-largest', const Size(320, 900), 2.0),
      ('tablet', const Size(1280, 800), 1.0),
    ]) {
      testWidgets(
        '${dark ? "dark" : "light"} ${config.$1}: ingredient actions stay on one line',
        (tester) async {
          await _fonts(tester);
          tester.view.physicalSize = config.$2;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final (c, _, _) = await controller();
          final rows = c.draft.sections.first.rows;
          rows.clear();
          rows.addAll([
            EditableIngredient(
              amount: '12',
              unit: 'oz',
              name: 'short pasta',
              prepNote: 'Use any short pasta shape.',
              showNote: true,
            ),
            EditableIngredient(amount: '1', unit: 'lb', name: 'ground beef'),
          ]);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: cookdexTheme(
                  colors: dark ? cookdexColors : cookdexLightColors,
                ),
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
          for (var i = 0; i < rows.length; i++) {
            final controls = find.byKey(ValueKey('${rows[i].id}-controls'));
            await reveal(tester, controls);
            final drag = find.byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.label == 'Reorder ingredient ${i + 1}',
            );
            final delete = find.byTooltip('Delete ingredient ${i + 1}');
            final optional = find
                .ancestor(
                  of: find.descendant(
                    of: controls,
                    matching: find.text('Optional'),
                  ),
                  matching: find.byType(InkWell),
                )
                .first;
            final rects = [
              tester.getRect(drag),
              tester.getRect(optional),
              tester.getRect(delete),
            ];
            expect(rects[0].center.dy, rects[1].center.dy);
            expect(rects[1].center.dy, rects[2].center.dy);
            expect(rects[0].right, lessThanOrEqualTo(rects[1].left));
            for (final rect in rects) {
              expect(rect.width, greaterThanOrEqualTo(48));
              expect(rect.height, greaterThanOrEqualTo(48));
              expect(rect.left, greaterThanOrEqualTo(0));
              expect(rect.right, lessThanOrEqualTo(config.$2.width));
            }
            final label = tester.getRect(
              find.descendant(of: controls, matching: find.text('Optional')),
            );
            expect(label.right + 12, lessThanOrEqualTo(rects[2].left + .01));
          }
          await reveal(tester, find.byKey(ValueKey(rows.first.id)));
          await Scrollable.ensureVisible(
            tester.element(find.byKey(ValueKey(rows.first.id))),
            alignment: 0.08,
          );
          await tester.pumpAndSettle();
          Future<void> shot(String state) async {
            expect(tester.takeException(), isNull);
            if (Platform.environment['INGREDIENT_CONTROLS_SCREENSHOTS'] !=
                '1') {
              return;
            }
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const Key('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                '../artifacts/ingredient-controls/screens/${dark ? "dark" : "light"}-${config.$1}-$state.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await shot('idle');
          await tester.tap(find.byKey(ValueKey('${rows.first.id}-name')));
          await tester.pumpAndSettle();
          await shot('active');
        },
      );
    }
  }
}
