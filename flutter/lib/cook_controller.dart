import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_preferences.dart';
import 'src/rust/api.dart';

/// Cooking presentation state and serialized ownership of the native wake flag.
class CookController extends ChangeNotifier {
  CookController({required this.preferences, required this._setWake});
  final LocalPreferences preferences;
  final Future<void> Function(bool) _setWake;
  Recipe? _recipe;
  int scale = 2;
  bool active = false;
  int step = 0;
  Set<int> checkedIngredients = {};
  bool _visible = false, _resumed = true, _obscured = false;
  bool _shoppingVisible = false;
  bool _wakeApplied = false, _running = false, _disposed = false;
  int _intent = 0;
  String? wakeError;
  bool get canCook => (_recipe?.fields.steps.length ?? 0) > 0;
  int get stepCount => _recipe?.fields.steps.length ?? 0;
  bool get canPrevious => active && step > 0;
  bool get canNext => active && step + 1 < (_recipe?.fields.steps.length ?? 0);
  bool get _desired =>
      !_disposed &&
      ((active && canCook && _visible) || _shoppingVisible) &&
      _resumed &&
      !_obscured;

  void setShoppingVisible(bool enabled) {
    if (_shoppingVisible == enabled) return;
    _shoppingVisible = enabled;
    _changed();
  }

  void setRecipe(Recipe? recipe) {
    if (identical(recipe, _recipe)) return;
    final changed = recipe?.id != _recipe?.id;
    _recipe = recipe;
    if (changed) {
      active = false;
      step = recipe == null ? 0 : preferences.cookStep(recipe.id);
      checkedIngredients = recipe == null
          ? {}
          : preferences.cookChecks(recipe.id);
    }
    step = canCook ? step.clamp(0, recipe!.fields.steps.length - 1) : 0;
    checkedIngredients.removeWhere(
      (i) => i < 0 || i >= (recipe?.fields.ingredients.length ?? 0),
    );
    if (!canCook) active = false;
    _save();
    _changed();
  }

  void toggle() {
    if (!canCook) return;
    active = !active;
    _changed();
  }

  void selectStep(int value) {
    if (!active || !canCook) return;
    step = value.clamp(0, _recipe!.fields.steps.length - 1);
    _save();
    notifyListeners();
  }

  void previous() {
    if (canPrevious) selectStep(step - 1);
  }

  void next() {
    if (canNext) selectStep(step + 1);
  }

  void toggleIngredient(int index) {
    if (!active ||
        index < 0 ||
        index >= (_recipe?.fields.ingredients.length ?? 0)) {
      return;
    }
    if (!checkedIngredients.remove(index)) checkedIngredients.add(index);
    _save();
    notifyListeners();
  }

  void setVisibility({
    required bool visible,
    required bool resumed,
    required bool obscured,
  }) {
    if (_visible == visible && _resumed == resumed && _obscured == obscured) {
      return;
    }
    _visible = visible;
    _resumed = resumed;
    _obscured = obscured;
    _changed();
  }

  void retryWake() {
    wakeError = null;
    _changed();
  }

  void _save() {
    if (_recipe != null) {
      preferences.saveCook(_recipe!.id, step, checkedIngredients);
    }
  }

  void _changed() {
    _intent++;
    if (!_disposed) notifyListeners();
    unawaited(_reconcileWake());
  }

  Future<void> _reconcileWake() async {
    if (_running) return;
    _running = true;
    try {
      while (_wakeApplied != _desired || wakeError != null) {
        final wanted = _desired;
        final intent = _intent;
        try {
          await _setWake(wanted);
          _wakeApplied = wanted;
          wakeError = null;
        } catch (_) {
          wakeError =
              'Could not ${wanted ? 'keep the screen awake' : 'release the screen wake lock'}.';
          // An acquire may have partially succeeded. Always request release once
          // when the ownership intent changed while the platform was pending.
          if (intent != _intent) continue;
          break;
        }
        if (!_disposed) notifyListeners();
      }
    } finally {
      _running = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _intent++;
    unawaited(_reconcileWake());
    super.dispose();
  }
}
