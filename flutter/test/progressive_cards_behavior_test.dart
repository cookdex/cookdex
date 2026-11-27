import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/recipe_metadata.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart'
    show ImportRepositoryFake, ImportFakeService, ShellPlatform;
import 'support/polish_fixtures.dart' show polishRecipe;

const _title = 'Autumn vegetable and bean stew';
const _capture = Key('shell-screen-capture');

List<Recipe> _recipes() => [
  polishRecipe('0', _title),
  polishRecipe('1', 'Lemon chicken with fragrant garden herbs'),
  polishRecipe('2', 'Roasted vegetables and tender beans'),
  polishRecipe('3', 'Weekend tomato soup'),
];

class _Harness {
  _Harness(this.repository, this.store, this.preferences);
  final ImportRepositoryFake repository;
  final RecipeStore store;
  final LocalPreferences preferences;
  final opened = <String>[];
  final actions = <String>[];
  final selected = <String>{'0'};
}

Future<_Harness> _mount(
  WidgetTester tester, {
  int? Function(RecipeSummary)? force,
  bool selecting = false,
  bool wholeApp = false,
  ThemeMode mode = ThemeMode.light,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  ProgressiveCard.debugStageForRecipe = force;
  final preferences = LocalPreferences.memory()
    ..setView(RecipeView.cards)
    ..setSort(RecipeSort.title)
    ..setThemeMode(mode);
  final repository = ImportRepositoryFake(_recipes());
  final store = RecipeStore(repository, preferences);
  final harness = _Harness(repository, store, preferences);
  await store.initialize();
  addTearDown(() async {
    ProgressiveCard.debugStageForRecipe = null;
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    preferences.dispose();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: wholeApp
          ? CookdexApp(
              store: store,
              platform: ShellPlatform(),
              importService: ImportFakeService(),
            )
          : MaterialApp(
              theme: cookdexTheme(colors: cookdexLightColors)
                  .copyWith(platform: platform),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, update) => RecipesScreen(
                    store: store,
                    preferences: preferences,
                    selectedIds: selecting ? harness.selected : null,
                    onToggleSelection: (id) => update(() {
                      if (!harness.selected.remove(id)) {
                        harness.selected.add(id);
                      }
                    }),
                    onCloseSelection: selecting ? () {} : null,
                    onOpenRecipe: harness.opened.add,
                    onAdd: () {},
                    onActions: (recipe) => harness.actions.add(recipe.id),
                  ),
                ),
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

Finder _card([String id = '0']) => find.byKey(ValueKey(id));
Finder _inside(Finder matching, [String id = '0']) =>
    find.descendant(of: _card(id), matching: matching);

Future<void> _fonts() async {
  final sdk = Platform.environment['FLUTTER_SDK'];
  if (sdk == null || sdk.isEmpty) {
    throw StateError('Set FLUTTER_SDK for real fonts.');
  }
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
    final loader = FontLoader('packages/material_symbols_icons/$family');
    loader.addFont(
      rootBundle.load('packages/material_symbols_icons/lib/fonts/$family.ttf'),
    );
    await loader.load();
  }
}

void main() {
  setUp(() => ProgressiveCard.debugStageForRecipe = null);
  tearDown(() => ProgressiveCard.debugStageForRecipe = null);

  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('forced title-only shell exposes its title and opens on tap', (
    tester,
  ) async {
    phone(tester);
    final semantics = tester.ensureSemantics();
    try {
      // Force is intentional here: this checks shell semantics, not the normal
      // accessibility policy (which shows complete cards and is checked below).
      final harness = await _mount(tester, force: (_) => 0);
      expect(_inside(find.text(_title)), findsOneWidget);
      expect(
        _inside(find.text(_recipes().first.fields.description)),
        findsNothing,
      );
      expect(_inside(find.byType(RecipeMetadata)), findsNothing);
      expect(_inside(find.byType(RecipeTagLine)), findsNothing);
      expect(_inside(find.byType(IconButton)), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(_title))),
        findsWidgets,
      );
      await tester.tap(find.text(_title));
      expect(harness.opened, ['0']);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'Windows forced shell supports long press and secondary click actions',
    (tester) async {
      phone(tester);
      final harness = await _mount(
        tester,
        force: (_) => 0,
        platform: TargetPlatform.windows,
      );
      await tester.longPress(find.text(_title));
      await tester.pumpAndSettle();
      expect(harness.actions, ['0']);
      await tester.tap(find.text(_title), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(harness.actions, ['0', '0']);
      expect(harness.opened, isEmpty);
    },
  );

  testWidgets('Windows keyboard focus and Enter activate a forced shell', (
    tester,
  ) async {
    phone(tester);
    final harness = await _mount(
      tester,
      force: (_) => 0,
      platform: TargetPlatform.windows,
    );
    final focus = Focus.of(tester.element(find.text(_title)));
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(harness.opened, ['0']);
  });

  testWidgets(
    'selection shell keeps checkbox state and toggles without opening',
    (tester) async {
      phone(tester);
      final harness = await _mount(tester, force: (_) => 0, selecting: true);
      final checkbox = _inside(find.byType(Checkbox));
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      await tester.tap(find.text(_title));
      await tester.pumpAndSettle();
      expect(harness.selected, isEmpty);
      expect(tester.widget<Checkbox>(checkbox).value, isFalse);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(harness.selected, {'0'});
      expect(tester.widget<Checkbox>(checkbox).value, isTrue);
      expect(harness.opened, isEmpty);
    },
  );

  testWidgets(
    'semantics enabled without override presents usable complete cards',
    (tester) async {
      phone(tester);
      final semantics = tester.ensureSemantics();
      try {
        final harness = await _mount(tester);
        expect(ProgressiveCard.debugStageForRecipe, isNull);
        expect(
          _inside(find.text(_recipes().first.fields.description)),
          findsOneWidget,
        );
        expect(_inside(find.byType(RecipeMetadata)), findsOneWidget);
        expect(_inside(find.byType(RecipeTagLine)), findsOneWidget);
        expect(
          _inside(find.bySemanticsLabel('Unfavorite $_title')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(_title))),
          findsWidgets,
        );
        await tester.tap(_inside(find.bySemanticsLabel('Unfavorite $_title')));
        await tester.pumpAndSettle();
        expect(harness.repository.recipes['0']!.favorite, isFalse);
        expect(
          _inside(find.bySemanticsLabel('Favorite $_title')),
          findsOneWidget,
        );
        expect(harness.opened, isEmpty);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'mixed shell and finished list light and dark phone screenshots',
    (tester) async {
      phone(tester);
      await tester.runAsync(_fonts);
      final manifest = <Map<String, Object>>[];
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await _mount(
          tester,
          wholeApp: true,
          mode: mode,
          force: (recipe) => int.parse(recipe.id).isEven ? 0 : 4,
        );
        expect(_inside(find.text(_title)), findsOneWidget);
        expect(_inside(find.byType(RecipeMetadata)), findsNothing);
        expect(_inside(find.byType(RecipeMetadata), '1'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: mode.name);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final file = File(
              '../artifacts/large-library-scroll/shells/${mode.name}.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(
              (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
                  .asUint8List(),
            );
            manifest.add({
              'file': '${mode.name}.png',
              'width': image.width,
              'height': image.height,
              'forcedStages': 'even IDs 0; odd IDs 4',
              'scope': 'Real RecipesScreen visual states; no timing evidence.',
            });
          } finally {
            image.dispose();
          }
        });
      }
      await tester.runAsync(
        () => File(
          '../artifacts/large-library-scroll/shells/manifest.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(manifest)),
      );
      expect(manifest, hasLength(2));
    },
    skip: Platform.environment['LARGE_CARDS_SHELL_SCREENS'] != '1',
  );
}
