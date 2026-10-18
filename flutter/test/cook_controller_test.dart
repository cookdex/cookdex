import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/src/rust/api.dart';

import 'recipe_store_test.dart' show recipe, settle;

void main() {
  test(
    'shopping and cook share one wake owner across overlays and lifecycle',
    () async {
      final calls = <bool>[];
      final prefs = LocalPreferences.memory();
      final cook = CookController(
        preferences: prefs,
        setWake: (value) async {
          calls.add(value);
        },
      );
      cook.setVisibility(visible: false, resumed: true, obscured: false);
      cook.setShoppingVisible(true);
      await settle();
      expect(calls.last, true);
      cook.setVisibility(visible: false, resumed: true, obscured: true);
      await settle();
      expect(calls.last, false);
      cook.setVisibility(visible: false, resumed: true, obscured: false);
      await settle();
      expect(calls.last, true);
      cook.setVisibility(visible: false, resumed: false, obscured: false);
      await settle();
      expect(calls.last, false);
      cook.setShoppingVisible(false);
      cook.setRecipe(recipe('a'));
      cook.setVisibility(visible: true, resumed: true, obscured: false);
      cook.toggle();
      await settle();
      expect(calls.last, true);
      cook.dispose();
      await settle();
      expect(calls.last, false);
      prefs.dispose();
    },
  );
  test('cook bounds, ingredient checkoff and restored position', () {
    final prefs = LocalPreferences.memory();
    final cook = CookController(preferences: prefs, setWake: (_) async {});
    cook.setRecipe(recipe('a'));
    cook.toggle();
    cook.selectStep(99);
    expect(cook.step, 1);
    expect(cook.canNext, false);
    cook.next();
    expect(cook.step, 1);
    cook.previous();
    cook.previous();
    expect(cook.step, 0);
    cook.toggleIngredient(0);
    cook.toggleIngredient(99);
    expect(cook.checkedIngredients, {0});
    cook.selectStep(1);
    cook.setRecipe(recipe('b'));
    cook.setRecipe(recipe('a'));
    expect(cook.step, 1);
    expect(cook.checkedIngredients, {0});
    expect(cook.active, false);
    final original = recipe('empty');
    cook.setRecipe(
      Recipe(
        id: original.id,
        favorite: false,
        createdAt: '',
        updatedAt: '',
        revision: 1,
        fields: RecipeFields(
          title: 'No steps',
          description: '',
          servings: '',
          prepTime: '',
          cookTime: '',
          totalTime: '',
          source: '',
          tags: [],
          notes: '',
          ingredients: [],
          steps: [],
        ),
      ),
    );
    cook.toggle();
    expect(cook.active, false);
    expect(cook.canCook, false);
    cook.dispose();
    prefs.dispose();
  });
  test('wake ownership follows visibility, overlays, pause and exit', () async {
    final calls = <bool>[];
    final prefs = LocalPreferences.memory();
    final cook = CookController(
      preferences: prefs,
      setWake: (enabled) async {
        calls.add(enabled);
      },
    );
    cook.setRecipe(recipe('a'));
    cook.toggle();
    await settle();
    expect(calls, isEmpty);
    cook.setVisibility(visible: true, resumed: true, obscured: false);
    await settle();
    cook.setVisibility(visible: true, resumed: true, obscured: true);
    await settle();
    cook.setVisibility(visible: true, resumed: true, obscured: false);
    await settle();
    cook.setVisibility(visible: true, resumed: false, obscured: false);
    await settle();
    cook.setVisibility(visible: true, resumed: true, obscured: false);
    await settle();
    cook.setVisibility(visible: false, resumed: true, obscured: false);
    await settle();
    expect(calls, [true, false, true, false, true, false]);
    cook.dispose();
    prefs.dispose();
  });
  test(
    'late wake acquisition releases after visibility or disposal changes',
    () async {
      final gate = Completer<void>();
      final calls = <bool>[];
      final prefs = LocalPreferences.memory();
      final cook = CookController(
        preferences: prefs,
        setWake: (value) async {
          calls.add(value);
          if (value) await gate.future;
        },
      );
      cook.setRecipe(recipe('a'));
      cook.setVisibility(visible: true, resumed: true, obscured: false);
      cook.toggle();
      cook.dispose();
      gate.complete();
      await settle();
      expect(calls, [true, false]);
      prefs.dispose();
    },
  );
  test(
    'failed wake request reports error and explicit retry recovers',
    () async {
      var failing = true;
      final calls = <bool>[];
      final prefs = LocalPreferences.memory();
      final cook = CookController(
        preferences: prefs,
        setWake: (value) async {
          calls.add(value);
          if (failing) throw StateError('platform unavailable');
        },
      );
      cook.setRecipe(recipe('a'));
      cook.setVisibility(visible: true, resumed: true, obscured: false);
      cook.toggle();
      await settle();
      expect(cook.wakeError, isNotNull);
      failing = false;
      cook.retryWake();
      await settle();
      expect(cook.wakeError, isNull);
      expect(calls, [true, true]);
      cook.dispose();
      await settle();
      expect(calls.last, false);
      prefs.dispose();
    },
  );
  test(
    'late failed acquisition still requests release when obscured',
    () async {
      final gate = Completer<void>();
      final calls = <bool>[];
      final prefs = LocalPreferences.memory();
      final cook = CookController(
        preferences: prefs,
        setWake: (value) async {
          calls.add(value);
          if (value) await gate.future;
        },
      );
      cook.setRecipe(recipe('a'));
      cook.setVisibility(visible: true, resumed: true, obscured: false);
      cook.toggle();
      cook.setVisibility(visible: true, resumed: true, obscured: true);
      gate.completeError(StateError('failed'));
      await settle();
      expect(calls, [true, false]);
      expect(cook.wakeError, isNull);
      cook.dispose();
      prefs.dispose();
    },
  );
}
