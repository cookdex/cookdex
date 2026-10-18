import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_screen_test.dart' show item, setup;

void main() {
  testWidgets('shopping band rendered review matrix', (tester) async {
    if (Platform.environment['SHOPPING_POLISH_SCREENSHOTS'] != '1') return;
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
      ('small', const Size(320, 800), 1.0),
      ('normal', const Size(412, 892), 1.0),
      ('largest', const Size(412, 892), 2.0),
      ('tablet-landscape', const Size(1280, 800), 1.0),
    ]) {
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      const produce = [
        'Carrots',
        'Fresh flat-leaf parsley',
        'Apples',
        'Sweet potatoes',
        'Broccoli',
        'Red onions',
        'Lemons',
        'Cherry tomatoes',
        'Spinach',
        'Garlic',
      ];
      const pantry = [
        'Green lentils, rinsed and drained',
        'Coconut milk',
        'Brown rice',
        'Chickpeas',
        'Olive oil',
        'Rolled oats',
        'Whole wheat flour',
        'Tahini',
      ];
      final (store, _) = await setup(
        [
          for (var i = 0; i < produce.length; i++)
            item(
              'p$i',
              produce[i],
              category: 'produce',
              quantity: i == 0 ? '2–3' : '1',
              sources: i.isEven ? ['a', 'b'] : [],
            ),
          for (var i = 0; i < pantry.length; i++)
            item(
              'g$i',
              pantry[i],
              category: 'pantry',
              quantity: i == 0 ? '1/2–1 1/2 cups' : '1',
            ),
          item('soap', 'Dish soap'),
          item('towels', 'Paper towels'),
          for (var i = 0; i < 12; i++)
            item('c$i', 'Already packed item ${i + 1}', checked: true),
        ],
        categories: const [
          ShoppingCategory(id: 'produce', name: 'Produce'),
          ShoppingCategory(
            id: 'pantry',
            name: 'Pantry and international ingredients',
          ),
          ShoppingCategory(id: 'other', name: 'Other'),
        ],
      );
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              // Recipe text preferences do not scale shopping controls or rows.
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(config.$3)),
              child: child!,
            ),
            home: ShoppingScreen(store: store, onSaveText: (_) async {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> shot(String name) async {
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/performance-polish/shopping/screens/${config.$1}-$name.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      final scrollable = find.byType(Scrollable).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final viewportTop = tester.getTopLeft(scrollable).dy;
      await shot('initial');
      position.jumpTo(180);
      await tester.pumpAndSettle();
      // Exercise a real check and render the settled updated unchecked count.
      await store.editShopping(
        const ShoppingEdit.check(ids: ['p0'], checked: true),
      );
      await tester.pumpAndSettle();
      await shot('pinned-after-check');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('shopping-row-g0-false')),
        180,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final pantryHeight = tester
          .renderObject<RenderSliver>(
            find.byKey(const ValueKey('pinned-shopping-pantry')),
          )
          .geometry!
          .scrollExtent;
      final pantryTop =
          tester
              .getTopLeft(find.byKey(const ValueKey('shopping-row-g0-false')))
              .dy -
          pantryHeight;
      position.jumpTo(position.pixels + pantryTop - viewportTop - 20);
      await tester.pumpAndSettle();
      await shot('category-push-off');
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checked (13)'));
      await tester.pumpAndSettle();
      // ExpansionTile text starts below its top inset; align the tile itself.
      final tile = find.ancestor(
        of: find.text('Checked (13)'),
        matching: find.byType(ExpansionTile),
      );
      final tileTop = tester.getTopLeft(tile).dy;
      position.jumpTo(position.pixels + tileTop - viewportTop - 20);
      await tester.pumpAndSettle();
      await shot('checked-boundary');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
