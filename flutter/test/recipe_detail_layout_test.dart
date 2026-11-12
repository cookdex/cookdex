import 'dart:async';
import 'dart:typed_data';

import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Recipe _recipe({String source = 'https://example.com/garden-soup'}) => Recipe(
  id: 'layout-fixture',
  favorite: false,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-02',
  revision: 1,
  fields: RecipeFields(
    title: 'Garden soup',
    description: 'A warming bowl with plenty of vegetables.',
    servings: '4 bowls',
    prepTime: '10 min',
    cookTime: '20 min',
    totalTime: '30 min',
    source: source,
    tags: const ['dinner', 'soup'],
    notes: 'Keep chilled and reheat gently.',
    ingredients: List.generate(
      35,
      (i) => Ingredient(
        amount: const Amount.rational(numerator: 1, denominator: 1),
        unit: 'cup',
        name: 'vegetable $i',
        prepNote: 'cut into small pieces',
        optional: false,
        section: '',
      ),
    ),
    steps: List.generate(
      35,
      (i) =>
          'Step $i: Gently stir the vegetables over medium heat until tender, '
          'then add the remaining ingredients and cook until combined.',
    ),
  ),
);

class _Repository implements RecipeRepository {
  _Repository(this.recipe);
  final Recipe recipe;
  final events = StreamController<CollectionEvent>.broadcast();
  @override
  Future<CollectionSnapshot> snapshot() async => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: 0,
    summaries: [
      RecipeSummary(
        id: recipe.id,
        title: recipe.fields.title,
        description: recipe.fields.description,
        ingredients: recipe.fields.ingredients.map((i) => i.name).toList(),
        tags: recipe.fields.tags,
        notes: recipe.fields.notes,
        favorite: recipe.favorite,
        createdAt: recipe.createdAt,
        updatedAt: recipe.updatedAt,
        servings: recipe.fields.servings,
        prepTime: recipe.fields.prepTime,
        cookTime: recipe.fields.cookTime,
        totalTime: recipe.fields.totalTime,
        revision: recipe.revision,
      ),
    ],
    shopping: [],
    conflicts: [],
    hasPrevious: false,
  );
  @override
  Stream<CollectionEvent> subscribe() => events.stream;
  @override
  Future<Recipe?> detail(String id) async => recipe;
  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async =>
      List.filled(ingredients.length, '1');
  @override
  Future<CollectionSnapshot> favorite(int generation, String id, bool value) =>
      throw UnimplementedError();
  @override
  Future<CollectionSnapshot> delete(int generation, String id) =>
      throw UnimplementedError();
  @override
  Future<BackupPreview> previewRestore(Uint8List bytes) =>
      throw UnimplementedError();
  @override
  Future<CollectionSnapshot> restore(BackupPreview preview) =>
      throw UnimplementedError();
  @override
  Future<void> close() => events.close();
}

Future<CookController> _mount(
  WidgetTester tester,
  Size size, {
  double scale = 1,
  double railWidth = 0,
  double bottomInset = 0,
  bool reduceMotion = false,
  TargetPlatform platform = TargetPlatform.android,
  ValueChanged<double>? onControlsHeight,
  Recipe? recipe,
  Future<void> Function(String)? onSource,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final preferences = LocalPreferences.memory();
  final store = RecipeStore(_Repository(recipe ?? _recipe()), preferences);
  final cook = CookController(preferences: preferences, setWake: (_) async {});
  await store.initialize();
  addTearDown(() {
    cook.dispose();
    store.dispose();
    preferences.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme().copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: EdgeInsets.only(bottom: bottomInset),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Row(
          children: [
            SizedBox(width: railWidth),
            Expanded(
              child: RecipeDetail(
                store: store,
                recipeId: 'layout-fixture',
                cook: cook,
                onBack: () {},
                onActions: () {},
                onEdit: () {},
                onSource: onSource ?? (_) async {},
                onAddToShopping: () {},
                onControlsHeight: onControlsHeight,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cook;
}

Finder _overview() =>
    find.byKey(const PageStorageKey('recipe-overview-layout-fixture'));
Finder _directions() =>
    find.byKey(const PageStorageKey('recipe-directions-layout-fixture'));
Finder _barTitleOpacity() => find.ancestor(
  of: find.byKey(const Key('recipe-bar-title')),
  matching: find.byType(AnimatedOpacity),
);

Future<void> _resize(WidgetTester tester, double width) async {
  final size = Size(width, 760);
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

void main() {
  for (final (source, opens) in [
    ('http://example.org/recipe', true),
    ('https://example.org/recipes?dish=soup#tips', true),
    ('The neighborhood cookbook, page 21', false),
    ('https://example.org/soup from the spring issue', false),
    ('example.org/recipes', false),
    ('file:///recipes/soup.txt', false),
    ('mailto:editor@example.org', false),
    ('https:///missing-host', false),
    ('https://example.org:99999/soup', false),
    ('https://example.org/<book>', false),
  ]) {
    testWidgets('Source opens only a complete web address: $source', (
      tester,
    ) async {
      final opened = <String>[];
      await _mount(
        tester,
        const Size(390, 760),
        recipe: _recipe(source: source),
        onSource: (value) async => opened.add(value),
      );
      final value = find.text(source);
      final button = find.ancestor(
        of: value,
        matching: find.byType(TextButton),
      );
      expect(button, opens ? findsOneWidget : findsNothing);
      expect(find.text('Source'), opens ? findsNothing : findsOneWidget);
      await tester.ensureVisible(value);
      await tester.pumpAndSettle();
      await tester.tap(value);
      expect(opened, opens ? [source] : isEmpty);
    });
  }

  testWidgets('compact keeps its fading title and full-width cooking footer', (
    tester,
  ) async {
    final cook = await _mount(tester, const Size(390, 760));
    final titleOpacity = find.ancestor(
      of: find.byKey(const Key('recipe-bar-title')),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(titleOpacity).opacity, 0);
    final toolbar = tester.getRect(find.byKey(const Key('recipe-toolbar')));
    final scroll = find.byKey(const PageStorageKey('recipe-layout-fixture'));
    await tester.drag(scroll, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(titleOpacity).opacity, 1);
    expect(tester.getRect(find.byKey(const Key('recipe-toolbar'))), toolbar);
    final position = tester
        .widget<SingleChildScrollView>(scroll)
        .controller!
        .offset;
    expect(find.byTooltip('Edit recipe'), findsNothing);
    final toggleRect = tester.getRect(find.byKey(const Key('cook-toggle')));
    await tester.tap(find.text('Cook'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SingleChildScrollView>(scroll).controller!.offset,
      isNot(position),
    );
    expect(tester.getRect(find.byKey(const Key('cook-toggle'))), toggleRect);
    expect(find.byTooltip('Edit recipe'), findsNothing);
    final footer = tester.getRect(find.byType(CookNavigation));
    expect(footer.left, 0);
    expect(footer.right, 390);
    expect(footer.bottom, 760);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(cook.step, 1);
    final firstBadge = find
        .ancestor(of: find.text('1').last, matching: find.byType(Container))
        .first;
    final decoration =
        tester.widget<Container>(firstBadge).decoration! as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.color, Colors.transparent);
    final controller = tester.widget<SingleChildScrollView>(scroll).controller!;
    controller.jumpTo(0);
    await tester.pump();
    await tester.tap(find.byKey(const Key('cook-progress')));
    await tester.pumpAndSettle();
    expect(find.text(_recipe().fields.steps[1]).hitTestable(), findsOneWidget);
    expect(controller.offset, isNot(position));
    await tester.tap(find.text('Cooking'));
    await tester.pumpAndSettle();
    expect(controller.offset, position);
    await tester.tap(find.text('Cook'));
    await tester.pumpAndSettle();
    expect(find.text(_recipe().fields.steps[1]).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ingredient indent and entry scroll continue after the Cook pill settles',
    (tester) async {
      final cook = await _mount(tester, const Size(390, 844));
      final label = find.text('1 cup vegetable 0');
      final startX = tester.getTopLeft(label).dx;
      final pane = find.byKey(const PageStorageKey('recipe-layout-fixture'));
      final scroll = tester.widget<SingleChildScrollView>(pane).controller!;
      cook.toggle();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      final ring = find.byIcon(Symbols.radio_button_unchecked).first;
      expect(
        tester.getTopRight(ring).dx,
        lessThan(tester.getTopLeft(label).dx),
      );
      await tester.pump(const Duration(milliseconds: 125));
      expect(tester.getTopLeft(label).dx, closeTo(startX + 18, 1));
      final middle = scroll.offset;
      expect(middle, greaterThan(0));
      final pill = find.byKey(const Key('cook-controls-card'));
      final settledPill = tester.getRect(pill);
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getTopLeft(label).dx, closeTo(startX + 36, 1));
      expect(tester.getRect(pill), settledPill);
      expect(scroll.offset, greaterThan(middle));
      cook.toggle();
      await tester.pump();
      expect(find.text('Next').hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 125));
      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('of 35'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      await tester.pump(const Duration(milliseconds: 125));
      expect(tester.getTopLeft(label).dx, closeTo(startX + 18, 1));
      expect(scroll.offset, 0);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(label).dx, startX);
      expect(scroll.offset, 0);
    },
  );
  for (final expanded in [false, true]) {
    testWidgets(
      'Cook exit restores each reading pane after partial entry and scrolling to the end, expanded=$expanded',
      (tester) async {
        final cook = await _mount(tester, Size(expanded ? 1200 : 390, 844));
        ScrollController controller(Finder pane) =>
            tester.widget<SingleChildScrollView>(pane).controller!;
        final overview = controller(
          expanded
              ? _overview()
              : find.byKey(const PageStorageKey('recipe-layout-fixture')),
        );
        final directions = expanded ? controller(_directions()) : overview;
        overview.jumpTo(180);
        if (expanded) directions.jumpTo(320);
        await tester.pumpAndSettle();
        final overviewReading = overview.offset;
        final directionsReading = directions.offset;
        cook.toggle();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 125));
        final partial = overview.offset;
        expect(partial, isNot(overviewReading));
        cook.toggle();
        await tester.pumpAndSettle();
        expect(overview.offset, overviewReading);
        expect(directions.offset, directionsReading);

        cook.toggle();
        await tester.pumpAndSettle();
        directions.jumpTo(directions.position.maxScrollExtent);
        if (expanded) overview.jumpTo(overview.position.maxScrollExtent);
        await tester.pump();
        expect(directions.offset, greaterThan(directionsReading));
        cook.toggle();
        await tester.pump();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 90));
          expect(directions.offset, directionsReading);
          expect(overview.offset, overviewReading);
        }
      },
    );
  }
  testWidgets('narrow Windows keeps Edit in the same position while cooking', (
    tester,
  ) async {
    final cook = await _mount(
      tester,
      const Size(390, 760),
      platform: TargetPlatform.windows,
    );
    final edit = find.byTooltip('Edit recipe');
    final original = tester.getRect(edit);
    cook.toggle();
    await tester.pumpAndSettle();
    expect(tester.getRect(edit), original);
    expect(edit.hitTestable(), findsOneWidget);
  });

  testWidgets('detail grows ingredients then steps beside the rail', (
    tester,
  ) async {
    const railWidth = 120.0;
    await _mount(tester, const Size(839, 760), railWidth: railWidth);
    expect(find.byKey(const Key('recipe-overview-pane')), findsNothing);
    expect(
      find.byKey(const PageStorageKey('recipe-layout-fixture')),
      findsOneWidget,
    );
    Rect overviewRect() =>
        tester.getRect(find.byKey(const Key('recipe-overview-pane')));
    Rect directionsRect() =>
        tester.getRect(find.byKey(const Key('recipe-directions-pane')));
    void expectGutterAndAlignment() {
      expect(directionsRect().left - overviewRect().right, 24);
      expect(tester.getTopLeft(find.text('Steps')).dx, directionsRect().left);
      expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 0);
      expect(tester.takeException(), isNull);
    }

    await _resize(tester, 840);
    expect(overviewRect().width, 364);
    expect(overviewRect().left, railWidth + 16);
    expect(directionsRect().width, 300);
    expectGutterAndAlignment();
    await _resize(tester, 896);
    expect(overviewRect().width, 420);
    expect(directionsRect().width, 300);
    expect(overviewRect().left, railWidth + 16);
    expectGutterAndAlignment();
    await _resize(tester, 956);
    expect(overviewRect().width, 420);
    expect(directionsRect().width, 360);
    expect(overviewRect().left, railWidth + 16);
    expectGutterAndAlignment();

    await _resize(tester, 2400);
    final readingCap = directionsRect().width;
    expect(overviewRect().width, 420);
    expect(
      tester.getSize(find.byKey(const Key('recipe-readable-directions'))).width,
      readingCap,
    );
    expectGutterAndAlignment();

    // Ingredients are already capped when the steps reach their reading cap.
    final stepsFilledWidth = railWidth + 32 + 420 + 24 + readingCap;
    await _resize(tester, stepsFilledWidth);
    expect(overviewRect().width, closeTo(420, .001));
    expect(overviewRect().left, closeTo(railWidth + 16, .001));
    expect(directionsRect().width, closeTo(readingCap, .001));
    expectGutterAndAlignment();

    // After both panes fill, extra width surrounds their combined layout.
    final wideWidth = stepsFilledWidth + 400;
    await _resize(tester, wideWidth);
    expect(overviewRect().width, 420);
    expect(directionsRect().width, closeTo(readingCap, .001));
    expect(overviewRect().left - railWidth, closeTo(216, .001));
    expect(wideWidth - directionsRect().right, closeTo(216, .001));
    expectGutterAndAlignment();
  });

  for (final reduceMotion in [false, true]) {
    testWidgets(
      'Cook reveals the final instruction with reduce motion $reduceMotion',
      (tester) async {
        final cook = await _mount(
          tester,
          const Size(390, 844),
          reduceMotion: reduceMotion,
        );
        cook.toggle();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final entry = tester.widget<FractionalTranslation>(
          find
              .ancestor(
                of: find.byType(CookNavigation),
                matching: find.byType(FractionalTranslation),
              )
              .first,
        );
        if (reduceMotion) {
          expect(entry.translation, Offset.zero);
        } else {
          expect(entry.translation.dy, inExclusiveRange(0, 1));
        }
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<SingleChildScrollView>(
              find.byKey(const PageStorageKey('recipe-layout-fixture')),
            )
            .controller!;
        cook.selectStep(34);
        await tester.pump();
        expect(scroll.position.isScrollingNotifier.value, !reduceMotion);
        await tester.pumpAndSettle();
        final step = tester.getRect(find.text(_recipe().fields.steps.last));
        final pill = tester.getRect(
          find.byKey(const Key('cook-controls-card')),
        );
        expect(step.bottom, lessThan(pill.top));
        expect(
          step.top,
          greaterThanOrEqualTo(
            tester.getRect(find.byKey(const Key('recipe-toolbar'))).bottom,
          ),
        );
        expect(find.text('Step 35'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('expanded ingredient and direction panes scroll independently', (
    tester,
  ) async {
    await _mount(tester, const Size(1200, 760));
    final overview = tester
        .widget<SingleChildScrollView>(_overview())
        .controller!;
    final directions = tester
        .widget<SingleChildScrollView>(_directions())
        .controller!;
    await tester.drag(_directions(), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(directions.offset, greaterThan(0));
    expect(overview.offset, 0);
    expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 0);
    final directionOffset = directions.offset;
    await tester.drag(_overview(), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(overview.offset, greaterThan(0));
    expect(directions.offset, directionOffset);
    expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 1);
    directions.jumpTo(directions.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(
      find.text('Keep chilled and reheat gently.').hitTestable(),
      findsOneWidget,
    );
    expect(
      find.text('https://example.com/garden-soup').hitTestable(),
      findsOneWidget,
    );
    overview.jumpTo(overview.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('Add to shopping list').hitTestable(), findsOneWidget);
    overview.jumpTo(0);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 0);
  });

  testWidgets(
    'toolbar title waits for the whole title and tracks pane resize',
    (tester) async {
      await _mount(tester, const Size(1200, 760));
      final overview = tester
          .widget<SingleChildScrollView>(_overview())
          .controller!;
      final contentTitle = find.descendant(
        of: _overview(),
        matching: find.text('Garden soup'),
      );
      final titleHeight = tester.getSize(contentTitle).height;
      final toolbar = tester.getRect(find.byKey(const Key('recipe-toolbar')));
      overview.jumpTo(titleHeight + 11);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 0);
      overview.jumpTo(titleHeight + 13);
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 1);
      expect(tester.getRect(find.byKey(const Key('recipe-toolbar'))), toolbar);
      await _resize(tester, 390);
      expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 0);
      await _resize(tester, 1200);
      expect(tester.widget<AnimatedOpacity>(_barTitleOpacity()).opacity, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expanded Cook checks left ingredients and pins right controls', (
    tester,
  ) async {
    final measuredHeights = <double>[];
    final cook = await _mount(
      tester,
      const Size(1200, 760),
      bottomInset: 28,
      onControlsHeight: measuredHeights.add,
    );
    await tester.tap(find.text('Cook'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit recipe'), findsOneWidget);
    final controls = tester.getRect(find.byType(CookNavigation));
    final right = tester.getRect(
      find.byKey(const Key('recipe-directions-pane')),
    );
    expect(controls.left, right.left);
    expect(controls.right, right.right);
    expect(controls.bottom, right.bottom);
    expect(measuredHeights.last, controls.height);
    expect(
      tester.getRect(find.widgetWithText(FilledButton, 'Next')).bottom,
      lessThanOrEqualTo(controls.bottom - 28),
    );
    await tester.tap(find.text('1 cup vegetable 0'));
    await tester.pumpAndSettle();
    expect(cook.checkedIngredients, contains(0));
    await tester.drag(_directions(), const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(CookNavigation)), controls);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(cook.step, 1);
    expect(find.text('Step 2'), findsOneWidget);
    expect(find.text('1 cup vegetable 0').hitTestable(), findsOneWidget);
    cook.selectStep(34);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(cook.active, isFalse);
    expect(find.byType(CookNavigation), findsNothing);
    expect(find.text('Cook'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '840dp expanded Cook remains usable with large accessibility text',
    (tester) async {
      final cook = await _mount(tester, const Size(840, 760), scale: 2);
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();
      expect(find.text('Next').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(cook.step, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
