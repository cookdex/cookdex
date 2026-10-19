import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/help_content.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show reveal;
import 'import_test.dart' show ImportFakeService, ShellPlatform;
import 'support/polish_fixtures.dart';
import 'recipe_store_test.dart' show summary;

class _Platform extends ShellPlatform {
  _Platform(this.android);
  final bool android;
  @override
  bool get isAndroid => android;
}

class _Repository extends PolishRepository {
  _Repository() {
    recipes.clear();
    final json = recipeToJson(polishRecipe('0', 'Pantry tomato supper'));
    final fields = json['fields'] as Map<String, dynamic>;
    fields['description'] = 'An easy supper with tomatoes, salsa and beans.';
    fields['steps'] = [
      'Simmer: Combine the ingredients and heat gently.',
      'Serve: Spoon into bowls.',
    ];
    fields['ingredients'] = [
      for (final entry in [
        (1, '(16 oz) jars', 'salsa'),
        (2, '(14 oz) can', 'tomatoes'),
        (1, '(28 oz) can', 'tomatoes'),
      ])
        {
          'amount': {
            'kind': 'rational',
            'numerator': entry.$1,
            'denominator': 1,
          },
          'unit': entry.$2,
          'name': entry.$3,
          'prepNote': '',
          'optional': false,
          'section': '',
        },
    ];
    recipes['0'] = recipeFromJson(json);
    recipes['1'] = polishRecipe('1', 'Bean and tomato soup');
  }

  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async =>
      [
        for (final ingredient in ingredients)
          if (ingredient.amount case Amount_Rational(
            :final numerator,
            :final denominator,
          ))
            denominator == 1 ? '$numerator' : '$numerator/$denominator'
          else
            '1',
      ];

  @override
  CollectionSnapshot get current {
    return CollectionSnapshot(
      generation: generation,
      summaries: recipes.values.map(summary).toList(),
      shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
      shopping: [
        for (final entry in [
          ('same', '3 (14 oz) cans', false),
          ('different', '1 (28 oz) can', false),
          ('salsa', '1 (16 oz) jar', true),
        ])
          ShoppingItem(
            id: entry.$1,
            categoryId: 'other',
            name: entry.$3 ? 'salsa' : 'tomatoes',
            quantityText: entry.$2,
            checked: false,
            measures: const [],
            contributorIds: entry.$1 == 'same' ? const ['0', '1'] : const ['0'],
            contributorScales: const [],
          ),
      ],
      conflicts: const [],
      setAsideCount: 0,
      hasPrevious: false,
    );
  }
}

void main() {
  testWidgets('help, package units and About rendered matrix', (tester) async {
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
    const channel = MethodChannel('com.sylph.cookdex.dev/platform');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'appVersion' ? '1.7.1+17001' : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final manifest = <String>[];
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final config in [
        ('small-phone', const Size(320, 800), 1.0),
        ('normal-phone', const Size(390, 844), 1.0),
        ('largest-phone', const Size(390, 844), 2.0),
        ('tablet-landscape', const Size(1280, 800), 1.0),
        ('desktop', const Size(1440, 900), 1.0),
      ]) {
        tester.view.physicalSize = config.$2;
        tester.platformDispatcher.textScaleFactorTestValue = config.$3;
        final prefs = LocalPreferences.memory()
          ..setThemeMode(mode)
          ..setRecipeTextSize(
            config.$3 == 2 ? RecipeTextSize.extraLarge : RecipeTextSize.normal,
          );
        final store = RecipeStore(_Repository(), prefs);
        await store.initialize();
        Future<void> mount(Widget child) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            RepaintBoundary(key: const Key('capture'), child: child),
          );
          await tester.pumpAndSettle();
        }

        Future<void> app() => mount(
          CookdexApp(
            store: store,
            platform: _Platform(config.$1 != 'desktop'),
            drafts: MemoryDraftStorage(),
            importDrafts: MemoryDraftStorage(),
            importService: ImportFakeService(),
          ),
        );
        Future<void> capture(String state) async {
          await tester.pumpAndSettle();
          final name = '${mode.name}-${config.$1}-$state.png';
          expect(tester.takeException(), isNull, reason: name);
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('capture')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final file = File('../artifacts/help-units-171/screens/$name');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
          manifest.add(name);
        }

        Future<void> show(Finder target, {double alignment = .15}) async {
          if (target.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              target,
              220,
              scrollable: find.byType(Scrollable).last,
            );
          }
          await Scrollable.ensureVisible(
            tester.element(target.first),
            alignment: alignment,
          );
          await tester.pumpAndSettle();
        }

        Future<void> tap(Finder target) async {
          await show(target);
          await tester.tap(target.first);
          await tester.pumpAndSettle();
        }

        if (config.$1 != 'desktop') {
          await mount(
            MaterialApp(
              theme: cookdexTheme(
                colors: mode == ThemeMode.dark
                    ? cookdexColors
                    : cookdexLightColors,
              ),
              home: HowCookdexWorksScreen(
                loadAppInfo: () async => 'Synthetic fixture',
                openUrl: (_) async {},
              ),
            ),
          );
          await capture('help-overview');
          await tap(find.text('Getting started'));
          await tap(find.text('Adding and editing recipes'));
          final bullets = helpSections
              .firstWhere((s) => s.id == 'adding')
              .paragraphs;
          await show(find.byKey(ValueKey('help-paragraph-${bullets[1]}')));
          await capture('help-bullets');
          await tap(find.text('Adding and editing recipes'));
          await tap(find.text('Problems and feedback'));
          await show(find.text(helpCopyAppInfo), alignment: .9);
          await capture('help-feedback');

          await app();
          await tap(find.text('Pantry tomato supper'));
          await show(find.text('Ingredients').first);
          await capture('recipe');
          await tap(find.text('Cook'));
          await show(find.text('Ingredients').first);
          await capture('cook');
          // Editing uses the actual app route and disposable memory draft.
          await tap(find.byTooltip('Edit recipe'));
          final editor = tester.widget<RecipeEditor>(find.byType(RecipeEditor));
          final rows = editor.controller.draft.sections.first.rows;
          rows[0].amount = '1 1/2';
          rows[0].unit = '(14 oz) cans';
          rows[1].amount = '6–7';
          rows[1].unit = '(14 oz) cans';
          editor.controller.changed();
          await tester.pumpAndSettle();
          final unit = find.byKey(ValueKey('${rows[0].id}-unit'));
          await reveal(tester, unit);
          await show(unit);
          await capture('editor-resting');
          await tester.tap(unit);
          await tester.pumpAndSettle();
          await capture('editor-active');

          await app();
          await tap(find.text('Shopping list').last);
          await capture('shopping');
        } else {
          await app();
        }
        await tap(find.text('Settings').last);
        await show(find.text('Share cookdex'), alignment: .4);
        await capture('about');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        store.dispose();
        prefs.dispose();
      }
    }
    expect(manifest.length, 74);
    await tester.runAsync(
      () =>
          File('../artifacts/help-units-171/screens/manifest.txt')
              .writeAsString('${manifest.join('\n')}\n'),
    );
  }, skip: Platform.environment['HELP_UNITS_SCREENSHOTS'] != '1');
}
