import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/prepared_card_title.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _capture = Key('staged-card-pixels');

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_SDK']!;
  final roboto = FontLoader('Roboto');
  for (final weight in ['regular', 'medium', 'bold']) {
    roboto.addFont(
      File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
  }
  await roboto.load();
  for (final family in ['MaterialSymbolsRounded', 'MaterialSymbolsOutlined']) {
    final font = FontLoader('packages/material_symbols_icons/$family');
    font.addFont(
      rootBundle.load('packages/material_symbols_icons/lib/fonts/$family.ttf'),
    );
    await font.load();
  }
}

List<RecipeSummary> _recipes() {
  // Same synthetic mixed fixture input accepted by the geometry host gate.
  final path = Platform.environment['CARD_GEOMETRY_FIXTURE']!;
  final records = jsonDecode(File(path).readAsStringSync()) as List<dynamic>;
  expect(records, hasLength(2500));
  return [
    for (final index in [0, 1, 2, 4, 6, 7, 9, 12])
      (() {
        final value = records[index] as Map<String, dynamic>;
        return RecipeSummary(
          id: value['id'] as String,
          title: value['title'] as String,
          description: value['description'] as String,
          ingredients: (value['ingredients'] as List<dynamic>).map((item) {
            if (item is String) return item;
            return (item as Map<String, dynamic>)['name'] as String;
          }).toList(),
          tags: (value['tags'] as List<dynamic>).cast<String>(),
          notes: value['notes'] as String,
          favorite: value['favorite'] as bool,
          createdAt: value['createdAt'] as String,
          updatedAt: value['updatedAt'] as String,
          servings: value['servings'] as String,
          prepTime: value['prepTime'] as String,
          cookTime: value['cookTime'] as String,
          totalTime: value['totalTime'] as String,
          revision: value['revision'] as int,
        );
      })(),
  ];
}

Future<(int, int, Uint8List)> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (image.width, image.height, data!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets('filled shells exactly match native full-card pixels', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    final recipes = _recipes();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var pairs = 0;
    for (final dark in [false, true]) {
      for (final config in [
        ('phone390', const Size(390, 844), 358.0, 1.0, false),
        ('largest390', const Size(390, 844), 358.0, 2.0, false),
        ('tablet1280', const Size(1280, 800), 408.0, 1.0, true),
      ]) {
        tester.view.physicalSize = config.$2;
        final theme = cookdexTheme(
          colors: dark ? cookdexColors : cookdexLightColors,
          largerBody: config.$5,
        );
        for (final recipe in recipes) {
          final label = 'dark=$dark ${config.$1} ${recipe.id}';
          final stage = ValueNotifier(0);
          Widget host(bool staged) => MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$4)),
                child: Scaffold(
                  body: Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(
                        builder: (context) => RepaintBoundary(
                          key: _capture,
                          child: SizedBox(
                            width: config.$3,
                            height: config.$5
                                ? recipeGridCardHeight(context)
                                : null,
                            child: staged
                                ? ValueListenableBuilder<int>(
                                    valueListenable: stage,
                                    builder: (context, value, _) =>
                                        recipeCardForTest(
                                          recipe,
                                          grid: config.$5,
                                          stage: value,
                                        ),
                                  )
                                : recipeCardForTest(recipe, grid: config.$5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpWidget(host(false));
          await tester.pumpAndSettle();
          expect(find.byType(PreparedCardTitle), findsNothing, reason: label);
          final fullBounds = tester.getRect(find.byKey(_capture));
          final expected = await _pixels(tester);
          // Remount once to enter the actual shell path, then retain its state
          // through every fill step, including the prepared final title/tags.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(host(true));
          await tester.pumpAndSettle();
          final shellState = tester.state(find.byType(ProgressiveCard));
          for (var next = 0; next <= 4; next++) {
            stage.value = next;
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$label stage=$next',
            );
            expect(
              tester.state(find.byType(ProgressiveCard)),
              same(shellState),
            );
            expect(
              find.byType(PreparedCardTitle),
              findsOneWidget,
              reason: label,
            );
            expect(
              tester.getRect(find.byKey(_capture)),
              fullBounds,
              reason: label,
            );
          }
          final actual = await _pixels(tester);
          expect(
            (actual.$1, actual.$2),
            (expected.$1, expected.$2),
            reason: label,
          );
          expect(actual.$3, expected.$3, reason: '$label raw RGBA pixels');
          pairs++;
          await tester.pumpWidget(const SizedBox());
          stage.dispose();
        }
      }
    }
    expect(pairs, 48);
  }, skip: Platform.environment['STAGED_CARDS_PIXELS'] != '1');
}
