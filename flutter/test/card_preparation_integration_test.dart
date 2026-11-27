import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/prepared_card_title.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'recipe_store_test.dart' show FakeRepository, recipe;

const _description =
    'Roasted vegetables with a bright lemon dressing and fragrant herbs for a generous family supper.';

Future<RecipeStore> _store() async {
  final preferences = LocalPreferences.memory();
  final store = RecipeStore(
    FakeRepository([
      for (var i = 0; i < 12; i++)
        recipe(
          '$i',
          title:
              'Slow roasted garden vegetables with lemon and fragrant herbs $i',
          description: _description,
        ),
    ]),
    preferences,
  );
  await store.initialize();
  addTearDown(() {
    store.dispose();
    preferences.dispose();
  });
  return store;
}

Widget _screen(
  RecipeStore store, {
  String identity = 'retained',
  String typography = '',
}) => MaterialApp(
  theme: cookdexTheme(colors: cookdexLightColors),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(boldText: typography == 'bold')
          .applyTextStyleOverrides(
            lineHeightScaleFactorOverride: typography == 'height' ? 1.6 : null,
            letterSpacingOverride: typography == 'letter' ? 2 : null,
            wordSpacingOverride: typography == 'word' ? 5 : null,
            paragraphSpacingOverride: null,
          ),
      child: Scaffold(
        body: RecipesScreen(
          key: ValueKey(identity),
          store: store,
          preferences: store.preferences,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (_) {},
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('actual RecipesScreen preparation uses capped card widths', (
    tester,
  ) async {
    await loadSectionCaptureFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => ProgressiveCard.debugStageForRecipe = null);
    final store = await _store();
    for (final width in [600.0, 930.0, 1000.0]) {
      tester.view.physicalSize = Size(width, 844);
      ProgressiveCard.debugStageForRecipe = (_) => 0;
      await tester.pumpWidget(_screen(store, identity: 'shell-$width'));
      final card = find.byKey(ValueKey(store.visibleRecipes.first.id));
      final shell = tester.getSize(card);
      final cache = tester
          .widget<ProgressiveCards>(find.byType(ProgressiveCards))
          .preparation
          .geometry;
      final geometry = cache.measurePrepared(store.visibleRecipes.first)!;
      expect(shell.width, 420);
      expect(geometry.title!.maxWidth, shell.width - 72);
      ProgressiveCard.debugStageForRecipe = (_) => 4;
      await tester.pumpWidget(_screen(store, identity: 'native-$width'));
      expect(
        tester.getSize(card),
        shell,
        reason: 'shell/native sizes at $width',
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, semanticsEnabled: false);

  testWidgets('mounted shells switch to full native accessibility typography', (
    tester,
  ) async {
    await loadSectionCaptureFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(() => ProgressiveCard.debugStageForRecipe = null);
    final store = await _store();
    for (final width in [390.0, 930.0]) {
      tester.view.physicalSize = Size(width, 844);
      for (final typography in ['bold', 'height', 'letter', 'word']) {
        final identity = '$width-$typography';
        ProgressiveCard.debugStageForRecipe = (_) => 0;
        await tester.pumpWidget(_screen(store, identity: identity));
        final retainedState = tester.state(find.byType(RecipesScreen));
        expect(find.byType(PreparedCardTitle), findsWidgets);
        await tester.pumpWidget(
          _screen(store, identity: identity, typography: typography),
        );
        expect(
          identical(tester.state(find.byType(RecipesScreen)), retainedState),
          isTrue,
        );
        expect(find.byType(PreparedCardTitle), findsNothing);
        expect(find.text(_description), findsWidgets);
        final cache = tester
            .widget<ProgressiveCards>(find.byType(ProgressiveCards))
            .preparation
            .geometry;
        expect(cache.measurePrepared(store.visibleRecipes.first), isNull);
        final card = find.byKey(ValueKey(store.visibleRecipes.first.id));
        final updatedSize = tester.getSize(card);
        ProgressiveCard.debugStageForRecipe = (_) => 4;
        await tester.pumpWidget(
          _screen(store, identity: 'native-$identity', typography: typography),
        );
        expect(
          tester.getSize(card),
          updatedSize,
          reason: '$typography $width native bounds',
        );
        expect(tester.takeException(), isNull);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  }, semanticsEnabled: false);
}
