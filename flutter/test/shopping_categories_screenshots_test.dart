import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:cookdex/src/rust/api.dart';

import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/components.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_screen_test.dart' show item, setup, menu;

void main() {
  testWidgets('A3 shopping screenshot matrix', (tester) async {
    if (Platform.environment['A3_SCREENSHOTS'] != '1') return;
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
    for (final config in [
      ('small', const Size(360, 800), 1.0, 1.0),
      ('normal', const Size(412, 892), 1.0, 1.0),
      ('largest', const Size(412, 892), 2.0, 1.3),
      ('tablet-landscape', const Size(1280, 800), 1.0, 1.0),
    ]) {
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      final (store, _) = await setup(
        [
          item(
            'carrots',
            'Carrots',
            quantity: '2–3',
            category: 'produce',
            sources: ['a'],
          ),
          item(
            'herbs',
            'Fresh flat-leaf parsley',
            quantity: '1 bunch',
            category: 'produce',
          ),
          item(
            'lentils',
            'Green lentils, rinsed and drained',
            quantity: '1/2–1 1/2 cups',
            category: 'pantry',
            sources: ['a', 'b'],
          ),
          item('soap', 'Dish soap'),
          item(
            'oil',
            'Olive oil',
            quantity: '2 tbsp',
            checked: true,
            category: 'pantry',
          ),
        ],
        categories: const [
          ShoppingCategory(id: 'produce', name: 'Produce'),
          ShoppingCategory(id: 'meat', name: 'Meat & seafood'),
          ShoppingCategory(id: 'dairy', name: 'Dairy & eggs'),
          ShoppingCategory(id: 'bakery', name: 'Bakery'),
          ShoppingCategory(id: 'pantry', name: 'Pantry'),
          ShoppingCategory(id: 'canned', name: 'Canned goods'),
          ShoppingCategory(id: 'spices', name: 'Spices & seasonings'),
          ShoppingCategory(id: 'frozen', name: 'Frozen'),
          ShoppingCategory(id: 'beverages', name: 'Beverages'),
          ShoppingCategory(id: 'household', name: 'Household'),
          ShoppingCategory(id: 'other', name: 'Other'),
        ],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('shopping-capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(config.$3)),
              child: RecipeTextScale(factor: config.$4, child: child!),
            ),
            home: ShoppingScreen(store: store, onSaveText: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> shot(String name) async {
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('shopping-capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/a3/screenshots/${config.$1}-$name.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await shot('list');
      final handle = find.descendant(
        of: find.byKey(const ValueKey('herbs')),
        matching: find.byType(ReorderableDelayedDragStartListener),
      );
      final start = tester.getCenter(handle);
      final destination = tester
          .getCenter(find.byKey(const ValueKey('lentils')))
          .dy;
      final drag = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      for (var step = 1; step <= 15; step++) {
        await drag.moveTo(
          Offset(start.dx, start.dy + (destination - start.dy) * step / 15),
        );
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await shot('cross-category-drag');
      await drag.up();
      await tester.pumpAndSettle();
      final listScroll = find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Checked (1)'),
        250,
        scrollable: listScroll,
      );
      await tester.tap(find.text('Checked (1)'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('2 tbsp Olive oil'),
        200,
        scrollable: listScroll,
      );
      await tester.pumpAndSettle();
      await shot('checked');
      await tester.scrollUntilVisible(
        find.text('2–3 Carrots'),
        -250,
        scrollable: listScroll,
      );
      await tester.longPress(find.text('2–3 Carrots'));
      await tester.pumpAndSettle();
      await shot('item-menu');
      await tester.tap(find.text('Move to category'));
      await tester.pumpAndSettle();
      await shot('move-chooser');
      await tester.scrollUntilVisible(
        find.text('Other').last,
        250,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.tap(find.text('Other').last);
      await tester.pumpAndSettle();
      await menu(tester, 'Categories');
      await shot('categories');
      await tester.tap(find.text('Produce'));
      await tester.pumpAndSettle();
      await shot('rename');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Produce options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await shot('delete');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      const customName = 'Specialty ingredients from the international grocery';
      await store.editShopping(
        const ShoppingEdit.addCategory(name: customName),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(customName),
        250,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            .last,
      );
      await tester.pumpAndSettle();
      await shot('custom-category');
      unawaited(
        confirmRestore(
          tester.element(find.byType(Scaffold).last),
          const RestoreReport(
            shoppingSetup: true,
            added: 50,
            updated: 2,
            skipped: 1,
            conflicts: ['conflict'],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await shot('restore-preview');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
