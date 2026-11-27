import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/ui/recipe_favorite_button.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;

Widget host({
  required bool candidate,
  bool favorite = false,
  bool dark = true,
  required VoidCallback onFavorite,
  required VoidCallback onRow,
  required VoidCallback onLongPress,
  FocusNode? focus,
}) {
  final theme = cookdexTheme(colors: dark ? cookdexColors : cookdexLightColors);
  final colors = theme.colorScheme;
  const title = 'Garden soup';
  final button = candidate
      ? RecipeFavoriteButton(
          key: const Key('star'),
          title: title,
          favorite: favorite,
          onPressed: onFavorite,
          focusNode: focus,
        )
      : IconButton(
          key: const Key('star'),
          tooltip: '${favorite ? 'Unfavorite' : 'Favorite'} $title',
          focusNode: focus,
          onPressed: onFavorite,
          icon: Icon(
            Symbols.star,
            fill: favorite ? 1 : 0,
            color: favorite ? colors.tertiary : colors.onSurfaceVariant,
          ),
        );
  return RepaintBoundary(
    key: const Key('capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(
        body: Center(
          child: Material(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 350,
              height: 92,
              child: InkWell(
                onTap: onRow,
                onLongPress: onLongPress,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Quick · Family dinner',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      button,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Favorite square corners, row gestures, keyboard and tooltip match IconButton',
    (tester) async {
      tester.view.physicalSize = const Size(390, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final signatures = <Object>[];
      final counts = <String, int>{};
      for (final candidate in [false, true]) {
        var favorites = 0, rows = 0, holds = 0;
        final focus = FocusNode();
        await tester.pumpWidget(
          host(
            candidate: candidate,
            onFavorite: () => favorites++,
            onRow: () => rows++,
            onLongPress: () => holds++,
            focus: focus,
          ),
        );
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byKey(const Key('star')));
        expect(rect.size, const Size(48, 48));
        final semantics = tester
            .getSemantics(find.byKey(const Key('star')))
            .getSemanticsData();
        signatures.add((
          semantics.label,
          semantics.tooltip,
          semantics.actions,
          semantics.flagsCollection.toStrings().join(','),
        ));
        var elements = 0;
        void visit(Element e) {
          elements++;
          e.visitChildren(visit);
        }

        visit(tester.element(find.byKey(const Key('star'))));
        counts[candidate ? 'candidate' : 'current'] = elements;
        for (final corner in [
          const Offset(1, 1),
          const Offset(47, 1),
          const Offset(1, 47),
          const Offset(47, 47),
        ]) {
          await tester.tapAt(rect.topLeft + corner);
          await tester.pumpAndSettle();
        }
        expect(favorites, 4);
        expect(rows, 0);
        expect(holds, 0);
        final press = await tester.startGesture(rect.center);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Favorite Garden soup'), findsOneWidget);
        expect(holds, 0);
        expect(favorites, 4);
        await press.up();
        await tester.pumpAndSettle();
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(favorites, 6);
        expect(rows, 0);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: rect.center);
        await tester.pump();
        await mouse.down(rect.center);
        await mouse.up();
        await tester.pumpAndSettle();
        expect(favorites, 7);
        expect(rows, 0);
        await mouse.removePointer();
        await tester.longPressAt(const Offset(55, 120));
        expect(holds, 1);
        expect(favorites, 7);
        await tester.pumpWidget(const SizedBox());
        focus.dispose();
      }
      expect(signatures[1], signatures[0]);
      final output = Platform.environment['STAR_FEEDBACK_OUTPUT'];
      if (output != null) {
        Directory(output).createSync(recursive: true);
        File('$output/element-counts.json')
            .writeAsStringSync(jsonEncode(counts));
      }
      expect(counts['candidate']!, lessThan(counts['current']!));
    },
  );

  testWidgets(
    'Favorite feedback matches IconButton side by side in every state',
    (tester) async {
      final output = Platform.environment['STAR_FEEDBACK_OUTPUT'];
      await loadSectionCaptureFonts(tester);
      tester.view.physicalSize = const Size(780, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previous = FocusManager.instance.highlightStrategy;
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      final manifest = <Map<String, Object>>[];
      try {
        for (final dark in [false, true]) {
          for (final favorite in [false, true]) {
            for (final state in [
              'idle',
              'pressed',
              'hover',
              'focus',
              'tooltip',
            ]) {
              final pixels = <List<int>>[];
              final focuses = [FocusNode(), FocusNode()];
              await tester.pumpWidget(
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    children: [
                      for (var i = 0; i < 2; i++)
                        Expanded(
                          child: KeyedSubtree(
                            key: ValueKey('panel-$i'),
                            child: host(
                              candidate: i == 1,
                              favorite: favorite,
                              dark: dark,
                              onFavorite: () {},
                              onRow: () {},
                              onLongPress: () {},
                              focus: focuses[i],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
              await tester.pumpAndSettle();
              for (final candidate in [false, true]) {
                final index = candidate ? 1 : 0;
                final focus = focuses[index];
                final panel = find.byKey(ValueKey('panel-$index'));
                Finder inside(Finder finder) =>
                    find.descendant(of: panel, matching: finder);
                final point = tester.getCenter(
                  inside(find.byKey(const Key('star'))),
                );
                TestGesture? touch, mouse;
                if (state == 'pressed' || state == 'tooltip') {
                  touch = await tester.startGesture(point);
                  await tester.pump();
                  await tester.pump(
                    Duration(milliseconds: state == 'tooltip' ? 650 : 120),
                  );
                  await tester.pump(const Duration(milliseconds: 160));
                  if (state == 'tooltip') {
                    expect(
                      inside(
                        find.text(
                          '${favorite ? 'Unfavorite' : 'Favorite'} Garden soup',
                        ),
                      ),
                      findsOneWidget,
                    );
                  }
                } else if (state == 'hover') {
                  mouse = await tester.createGesture(
                    kind: PointerDeviceKind.mouse,
                  );
                  await mouse.addPointer(location: point);
                  await mouse.moveTo(point);
                  await tester.pump();
                  await tester.pump(const Duration(milliseconds: 100));
                } else if (state == 'focus') {
                  focus.requestFocus();
                  await tester.pumpAndSettle();
                }
                final bytes = (await tester.runAsync(() async {
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                    inside(find.byKey(const Key('capture'))),
                  );
                  final image = await boundary.toImage();
                  final data = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  image.dispose();
                  return data!.buffer.asUint8List();
                }))!;
                final name =
                    '${dark ? 'dark' : 'light'}-${favorite ? 'favorite' : 'plain'}-$state-${candidate ? 'candidate' : 'current'}.png';
                if (output != null) {
                  Directory(output).createSync(recursive: true);
                  File('$output/$name').writeAsBytesSync(bytes);
                }
                pixels.add(bytes);
                await touch?.up();
                await mouse?.removePointer();
                focus.unfocus();
                await tester.pumpAndSettle();
              }
              await tester.pumpWidget(const SizedBox());
              for (final focus in focuses) {
                focus.dispose();
              }
              expect(
                pixels[1],
                pixels[0],
                reason: '$state dark=$dark favorite=$favorite',
              );
              manifest.add({
                'dark': dark,
                'favorite': favorite,
                'state': state,
                'byteIdentical': listEquals(pixels[0], pixels[1]),
              });
            }
          }
        }
      } finally {
        FocusManager.instance.highlightStrategy = previous;
      }
      if (output != null) {
        File('$output/manifest.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(manifest),
        );
      }
    },
    semanticsEnabled: false,
  );
}
