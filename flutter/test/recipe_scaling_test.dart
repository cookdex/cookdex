import 'dart:async';

import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;
import 'shopping_screen_test.dart' show FakeShoppingUndo;

class ScalingFake extends FakeRepository implements ScalingRepository {
  ScalingFake() : super([recipe('scale', title: "Mom's Taco Meat")]) {
    recipes['scale']!.fields.ingredients[0] = const Ingredient(
      amount: Amount.rational(numerator: 1, denominator: 3),
      unit: 'cup',
      name: 'cream [fresh]',
      prepNote: '',
      optional: false,
      section: '',
    );
  }
  int? addedScale;
  Completer<ScaledRecipeView>? scaleGate;
  @override
  Future<ScaledRecipeView> scaleRecipe(RecipeFields fields, int scale) async {
    final gate = scaleGate;
    scaleGate = null;
    if (gate != null) return gate.future;
    return ScaledRecipeView(
      quantities: [scale == 6 ? '1 cup' : '2/3 cup'],
      servings: scale == 6 ? '12' : '8',
    );
  }

  @override
  Future<ShoppingResult> addShoppingScaled(
    int generation,
    String id,
    List<int> indices,
    int scale,
  ) async {
    addedScale = scale;
    return ShoppingResult(snapshot: current, undo: FakeShoppingUndo([], []));
  }
}

void main() {
  testWidgets('scale carries into Cook and shopping then resets on reopen', (
    tester,
  ) async {
    final repo = ScalingFake();
    final prefs = LocalPreferences.memory();
    final store = RecipeStore(repo, prefs);
    await store.refresh();
    final cook = CookController(preferences: prefs, setWake: (_) async {});
    Future<void> mount() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => RecipeDetail(
                store: store,
                recipeId: 'scale',
                cook: cook,
                onBack: () {},
                onActions: () {},
                onEdit: () {},
                onSource: (_) async {},
                onAddToShopping: () => showShoppingSelection(
                  context,
                  store,
                  repo.recipes['scale']!,
                  scale: cook.scale,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await mount();
    await tester.tap(find.byKey(const Key('recipe-scale-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recipe-scale-4')));
    await tester.pumpAndSettle();
    expect(cook.scale, 4);
    expect(find.text('2/3 cup cream [fresh]'), findsOneWidget);
    final styledAmount =
        tester.widget<Text>(find.text('2/3 cup cream [fresh]')).textSpan!
            as TextSpan;
    expect(styledAmount.style!.fontWeight, FontWeight.w400);
    expect(styledAmount.children!.first.style!.fontWeight, FontWeight.w500);
    expect(styledAmount.children!.first.toPlainText(), '2/3 cup ');
    expect(find.text("Amounts in steps aren't scaled."), findsOneWidget);
    await tester.tap(find.byKey(const Key('cook-toggle')));
    await tester.pumpAndSettle();
    expect(cook.active, isTrue);
    expect(find.text('2/3 cup cream [fresh]'), findsOneWidget);
    await tester.ensureVisible(find.text('Add to shopping list'));
    await tester.tap(find.text('Add to shopping list'));
    await tester.pumpAndSettle();
    expect(find.text('2/3 cup'), findsOneWidget);
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(repo.addedScale, 4);

    // A refresh started at 2× must not overwrite a later completed 3× click.
    final refreshGate = Completer<ScaledRecipeView>();
    repo.scaleGate = refreshGate;
    repo.changed(recipe('scale', title: "Mom's Taco Meat", revision: 2));
    await store.refresh();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('recipe-scale-toggle')));
    await tester.tap(find.byKey(const Key('recipe-scale-toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('recipe-scale-6')));
    await tester.tap(find.byKey(const Key('recipe-scale-6')));
    await tester.pumpAndSettle();
    expect(cook.scale, 6);
    refreshGate.complete(
      const ScaledRecipeView(quantities: ['2/3 cup'], servings: '8'),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 cup cream [fresh]'), findsOneWidget);
    expect(find.text('2/3 cup cream [fresh]'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await mount();
    expect(cook.scale, 2);
    expect(find.text("Amounts in steps aren't scaled."), findsNothing);
    await tester.pumpWidget(const SizedBox());
    cook.dispose();
    store.dispose();
    prefs.dispose();
  });
}
