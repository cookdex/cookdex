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

void main() {
  testWidgets('section UI approval captures and interaction smoke', (
    tester,
  ) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    await loadSectionCaptureFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    tester.view.physicalSize = const Size(390, 844);
    for (final dark in [false, true]) {
      final (c, _, _) = await controller();
      final top = EditableSection(
        rows: [
          EditableIngredient(name: 'Flour', amount: '2', unit: 'cups'),
          EditableIngredient(name: 'Milk', amount: '1', unit: 'cup'),
          EditableIngredient(name: 'Egg', amount: '1'),
        ],
      );
      final topping = EditableSection(
        name: 'Topping',
        rows: [EditableIngredient(name: 'Berries', amount: '1', unit: 'cup')],
      );
      c.draft.title = 'Sunday pancakes';
      c.draft.sections
        ..clear()
        ..addAll([top, topping]);
      c.changed();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('capture'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: cookdexTheme(
              colors: dark ? cookdexColors : cookdexLightColors,
            ).copyWith(platform: TargetPlatform.android),
            home: RecipeEditor(controller: c),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> capture(String state) async {
        expect(tester.takeException(), isNull, reason: state);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/ingredient-sections/revision-5/screens/${dark ? 'dark' : 'light'}-$state.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await reveal(tester, find.text('Section'));
      await tester.tap(find.text('Section'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Batter',
      );
      await tester.pumpAndSettle();
      await capture('dialog');
      final beforePlacement = tester.getRect(
        find.byKey(ValueKey('${top.rows[1].id}-name')),
      );
      final formScroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final beforePlacementScroll = formScroll.pixels;
      await tester.tap(find.text('Choose spot'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(ValueKey('${top.rows[1].id}-name'))),
        beforePlacement,
      );
      expect(formScroll.pixels, beforePlacementScroll);
      expect(find.byKey(ValueKey('section-spot-${top.id}-3')), findsNothing);
      expect(
        find.byKey(ValueKey('section-spot-${topping.id}-0')),
        findsNothing,
      );
      expect(find.byKey(ValueKey('section-spot-${top.id}-0')), findsOneWidget);
      expect(
        find.byKey(ValueKey('section-spot-${topping.id}-1')),
        findsOneWidget,
      );
      final beforeNote = top.rows.first.showNote;
      await tester.tap(find.text('+ Note').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(top.rows.first.showNote, beforeNote);
      await tester.tap(
        find.byTooltip('Delete ingredient 1').first,
        warnIfMissed: false,
      );
      await tester.tap(find.byType(Checkbox).first, warnIfMissed: false);
      await tester.tap(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Semantics &&
                  w.properties.label == 'Reorder ingredient 1',
            )
            .first,
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(top.rows.length, 3);
      expect(top.rows.first.optional, false);
      expect(c.draft.sections.length, 2);
      expect(find.text('Tap where Batter starts'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(ValueKey('section-spot-${top.id}-1'))).height,
        greaterThanOrEqualTo(48),
      );
      final markerPill = tester.getRect(
        find
            .descendant(
              of: find.byKey(ValueKey('section-spot-${top.id}-1')),
              matching: find.byType(DecoratedBox),
            )
            .last,
      );
      final optionalLabel = tester.getRect(
        find.descendant(
          of: find.byKey(ValueKey('${top.rows.first.id}-controls')),
          matching: find.text('Optional'),
        ),
      );
      final nextFields = tester.getRect(
        find.byKey(ValueKey('${top.rows[1].id}-unit')),
      );
      expect(markerPill.top, greaterThan(optionalLabel.bottom));
      expect(markerPill.bottom, lessThan(nextFields.top));
      expect(
        markerPill.center.dy,
        closeTo((optionalLabel.bottom + nextFields.top) / 2, 2),
      );
      await capture('placement');
      await tester.tap(find.byKey(ValueKey('section-spot-${top.id}-1')));
      await tester.pumpAndSettle();
      expect(c.draft.sections[1].name, 'Batter');
      expect(c.draft.sections[1].rows.map((r) => r.name), ['Milk', 'Egg']);
      expect(top.rows.single.name, 'Flour');
      await capture('placed');
      final batter = c.draft.sections[1];
      formScroll.jumpTo(
        (formScroll.pixels - 180).clamp(0, formScroll.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      final handle = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Reorder section 2',
      );
      final heldBefore = tester.getRect(find.byKey(ValueKey(batter.id)));
      final scrollBeforeDrag = formScroll.pixels;
      final toppingBefore = tester
          .getTopLeft(find.byKey(ValueKey(topping.id)))
          .dy;
      final pointer = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 110));
      final toppingMidway = tester
          .getTopLeft(find.byKey(ValueKey('drag-section-${topping.id}')))
          .dy;
      await tester.pumpAndSettle();
      final toppingCollapsed = tester
          .getTopLeft(find.byKey(ValueKey('drag-section-${topping.id}')))
          .dy;
      expect(toppingMidway, lessThan(toppingBefore));
      expect(toppingMidway, greaterThan(toppingCollapsed));
      final heldOverlay = find.byKey(ValueKey('drag-section-${batter.id}'));
      expect(tester.getRect(heldOverlay), heldBefore);
      expect(formScroll.pixels, scrollBeforeDrag);
      expect(
        tester.widget<SliverOpacity>(find.byType(SliverOpacity).first).opacity,
        0,
      );
      final toppingOverlay = find.byKey(ValueKey('drag-section-${topping.id}'));
      final destination = Offset(
        tester.getCenter(handle).dx,
        tester.getCenter(toppingOverlay).dy + 2,
      );
      await pointer.moveTo(destination);
      await tester.pumpAndSettle();
      expect(formScroll.pixels, scrollBeforeDrag);
      final topCollapsed = tester.getRect(
        find.byKey(ValueKey('drag-section-${top.id}')),
      );
      final toppingMoved = tester.getRect(toppingOverlay);
      expect(toppingMoved.top - topCollapsed.bottom, closeTo(16, .1));
      expect(
        tester.getRect(heldOverlay).top - toppingMoved.bottom,
        closeTo(18, .1),
      );
      await capture('drag-collapsed');
      await pointer.up();
      await tester.pumpAndSettle();
      expect(c.draft.sections.last, same(batter));
      expect(
        tester.getTopLeft(find.byKey(ValueKey(batter.id))).dy,
        closeTo(56, 1),
      );
      expect(
        tester.widget<SliverOpacity>(find.byType(SliverOpacity).first).opacity,
        1,
      );
      // Cancellation restores the exact pre-drag viewport and group order.
      formScroll.jumpTo(
        (formScroll.pixels - 180).clamp(0, formScroll.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      final cancelHandle = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Reorder section 3',
      );
      final beforeCancel = c.draft.sections.map((s) => s.id).toList();
      final cancelScroll = formScroll.pixels;
      final canceled = await tester.startGesture(
        tester.getCenter(cancelHandle),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await canceled.cancel();
      await tester.pumpAndSettle();
      expect(c.draft.sections.map((s) => s.id), beforeCancel);
      expect(formScroll.pixels, cancelScroll);
      expect(find.byKey(ValueKey('drag-section-${batter.id}')), findsNothing);
      // Reproduce the last-section-at-top report, without moving the finger.
      await Scrollable.ensureVisible(
        tester.element(find.byKey(ValueKey(batter.id))),
        alignment: 0,
      );
      await tester.pumpAndSettle();
      final lastRect = tester.getRect(find.byKey(ValueKey(batter.id)));
      expect(lastRect.top, closeTo(56, 1));
      final lastPointer = await tester.startGesture(
        tester.getCenter(cancelHandle),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      for (final group in c.draft.sections) {
        final rect = tester.getRect(
          find.byKey(ValueKey('drag-section-${group.id}')),
        );
        expect(rect.top, greaterThanOrEqualTo(56));
        expect(rect.bottom, lessThanOrEqualTo(844));
      }
      await capture('drag-last-near-top');
      var editorRebuilds = 0;
      final beforeDragVersion = c.version;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (builtOnce &&
            [
              'RecipeEditor',
              '_EditorField',
              '_EditorScrollView',
            ].contains(element.widget.runtimeType.toString())) {
          editorRebuilds++;
        }
      };
      try {
        for (var i = 0; i < 30; i++) {
          await lastPointer.moveTo(
            Offset(40 + (i % 3) * 100, lastRect.center.dy + 20 + i * 6),
          );
          await tester.pump(const Duration(milliseconds: 16));
          final rect = tester.getRect(
            find.byKey(ValueKey('drag-section-${batter.id}')),
          );
          expect(rect.left, lastRect.left);
          expect(rect.right, lastRect.right);
        }
      } finally {
        debugOnRebuildDirtyWidget = null;
      }
      expect(
        editorRebuilds,
        0,
        reason: 'Pointer movement must rebuild only the drag layer',
      );
      expect(
        c.version,
        beforeDragVersion,
        reason: 'Drag hover must not persist draft changes',
      );
      await lastPointer.cancel();
      await tester.pumpAndSettle();
      // Show both distinct menu actions and the destructive confirmation.
      await tester.tap(find.byTooltip('Section 3 options'));
      await tester.pumpAndSettle();
      await capture('section-menu');
      await tester.tap(find.text('Delete section'));
      await tester.pumpAndSettle();
      expect(
        find.text('Delete “Batter” and all its ingredients?'),
        findsOneWidget,
      );
      await capture('delete-confirmation');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.draft.sections.last, same(batter));
      final movedRows = batter.rows.toList();
      await tester.tap(find.byTooltip('Section 3 options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove section'));
      await tester.pumpAndSettle();
      expect(c.draft.sections, [top, topping]);
      expect(topping.rows.skip(1), movedRows);
      await reveal(tester, find.byTooltip('Section 2 options'));
      await Scrollable.ensureVisible(
        tester.element(find.byKey(ValueKey(topping.id))),
        alignment: 0,
      );
      await tester.pumpAndSettle();
      await capture('section-removed');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(c.draft.sections, [top, topping, batter]);
      expect(batter.rows, movedRows);
      await reveal(tester, find.byTooltip('Section 3 options'));
      await tester.tap(find.byTooltip('Section 3 options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete section'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete section'));
      await tester.pumpAndSettle();
      expect(c.draft.sections, [top, topping]);
      expect(topping.rows.length, 1);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(c.draft.sections, [top, topping, batter]);
      expect(batter.rows, movedRows);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
    debugDisableShadows = true;
  }, skip: Platform.environment['SECTION_UI_SCREENSHOTS'] != '1');
}

Future<void> loadSectionCaptureFonts(WidgetTester tester) async {
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
      File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView),
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
