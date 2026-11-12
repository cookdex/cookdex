import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'create_preferences.dart';
import 'draft_storage.dart';
import 'import_diagnostics.dart';
import 'import_platform.dart';
import 'local_preferences.dart';
import 'smart_create_protocol.dart';
import 'src/rust/api.dart';
export 'smart_create_protocol.dart' show CreateIdea;

class _Cancelled implements Exception {
  const _Cancelled();
}

class _CreateError implements Exception {
  const _CreateError(this.message);
  final String message;
}

// Google includes generic help links and HTTP status names in its error
// envelope. Neither one describes why this particular request was refused.
String _providerProblem(List<int> bytes) {
  final raw = utf8.decode(bytes.take(32768).toList(), allowMalformed: true);
  try {
    final decoded = jsonDecode(raw);
    final error = decoded is Map ? decoded['error'] : null;
    if (error is! Map) return '';
    final parts = [if (error['message'] is String) error['message'] as String];
    final details = error['details'];
    if (details is List) {
      for (final detail in details.whereType<Map>()) {
        if (detail['reason'] is String) parts.add(detail['reason'] as String);
        final violations = detail['violations'];
        if (violations is List) {
          for (final v in violations.whereType<Map>()) {
            if ('${v['quotaValue']}' == '0') {
              parts.add('${v['quotaMetric']} limit: 0');
            }
          }
        }
      }
    }
    return parts.join(' ').toLowerCase();
  } on FormatException {
    return raw.toLowerCase();
  }
}

class SmartCreateController extends ChangeNotifier {
  SmartCreateController({
    required this.platform,
    required this.local,
    DraftStorage? diagnostics,
    this.existingTags,
  }) : _diagnostics = ImportDiagnosticsStore(
         diagnostics ?? MemoryDraftStorage(),
       ),
       _preferences = local.createPreferences,
       servings = local.createPreferences.servings {
    local.addListener(_settingsChanged);
  }
  final ImportPlatform platform;
  final LocalPreferences local;
  final Iterable<String> Function()? existingTags;
  String? progressAction, recipeWarning, reviewIdeaTitle;
  Future<void> Function()? onSuccessFlash;
  final savedRecipes = <String, String>{};
  final addedToList = <String>{};
  void markAdded(String title) {
    addedToList.add(title);
    notifyListeners();
  }

  void markSaved(String title, String id) {
    savedRecipes[title] = id;
    notifyListeners();
  }

  void forgetSavedRecipe(String id) {
    final count = savedRecipes.length;
    savedRecipes.removeWhere((_, savedId) => savedId == id);
    if (savedRecipes.length != count) notifyListeners();
  }

  CreateStep? _paidStep;
  bool get canUseFlash => _paidStep != null;
  Future<void> useFlash() async {
    final step = _paidStep;
    if (step == null) return;
    local.setCreatePreferences(
      preferences.withSelection(
        step,
        CreatePreferences.suggestedModel,
        CreatePreferences.suggestedThinking,
      ),
    );
    _clearMessage();
    notifyListeners();
  }

  void _phase(String text) {
    if (progress == text) return;
    progress = text;
    notifyListeners();
  }

  final ImportDiagnosticsStore _diagnostics;
  Future<String?> lastDiagnostic() => _diagnostics.read();
  Future<void> clearDiagnostic() => _diagnostics.clear();
  CreatePreferences _preferences;
  CreatePreferences get preferences => _preferences;
  int step = 0, servings;
  String typed = '', mood = '', meal = 'Any', effort = 'Any';
  static final _ingredientCharacter = RegExp(r'[^\s,]');
  bool get hasTypedIngredients => _ingredientCharacter.hasMatch(typed);
  bool get moodOnly =>
      mood.trim().isNotEmpty && !hasTypedIngredients && photos.isEmpty;
  List<ImportPhoto> photos = [];
  List<String> ingredients = [], maybe = [];
  Set<String> useFirst = {};
  List<CreateIdea> ideas = [];
  int _ideaBatchRevision = 0;
  int get ideaBatchRevision => _ideaBatchRevision;
  // The old batch stays committed until the button finishes flashing. The
  // Ideas page can paint the validated replacement as the flash starts.
  List<CreateIdea>? arrivingIdeas;
  final _shownIdeaTitles = <String>{};
  String? progress, error, notice;
  bool needsKey = false;
  int _epoch = 0;
  bool _picking = false, _disposed = false;
  bool _checked = false, _inputChanged = true, _servingsOverridden = false;
  String? _ideaInput;
  void _settingsChanged() {
    final p = local.createPreferences;
    if (identical(p, _preferences)) return;
    final rulesChanged =
        !listEquals(p.staples, _preferences.staples) ||
        !listEquals(p.avoid, _preferences.avoid) ||
        p.otherPreferences != _preferences.otherPreferences ||
        (!moodOnly && p.extraIngredients != _preferences.extraIngredients);
    final newServings = !_servingsOverridden && servings != p.servings;
    _preferences = p;
    if (newServings) servings = p.servings;
    if (rulesChanged || newServings) {
      if (progress != null) cancel();
      _invalidate();
      if (step == 2) step = moodOnly ? 0 : 1;
    }
    notifyListeners();
  }

  void _invalidate() {
    ideas = [];
    addedToList.clear();
    savedRecipes.clear();
    _ideaInput = null;
    notice = null;
  }

  void _clearMessage() {
    error = null;
    notice = null;
    needsKey = false;
    _paidStep = null;
  }

  void setTyped(String value) {
    if (typed == value) return;
    typed = value;
    _inputChanged = true;
    _clearMessage();
    notifyListeners();
  }

  void setMood(String value) {
    if (mood == value) return;
    if (progress != null) cancel();
    mood = value;
    _invalidate();
    _clearMessage();
    notifyListeners();
  }

  void toggleUseFirst(String name) {
    if (!ingredients.contains(name)) return;
    if (!useFirst.remove(name)) useFirst.add(name);
    _invalidate();
    notifyListeners();
  }

  void removeIngredient(String name) {
    ingredients.remove(name);
    useFirst.remove(name);
    _invalidate();
    notifyListeners();
  }

  void addIngredient(String name) {
    final value = name.trim();
    if (value.isEmpty) return;
    ingredients = distinctFoods([...ingredients, value]);
    maybe.removeWhere((s) => foodKey(s) == foodKey(value));
    _invalidate();
    notifyListeners();
  }

  void acceptMaybe(String name) => addIngredient(name);
  void setOptions({String? meal, String? effort, int? servings}) {
    if (meal != null) this.meal = meal;
    if (effort != null) this.effort = effort;
    if (servings != null) {
      this.servings = servings.clamp(1, 99);
      _servingsOverridden = true;
    }
    _invalidate();
    notifyListeners();
  }

  void back() {
    if (progress != null) {
      cancel();
      return;
    }
    _clearMessage();
    if (step > 0) step = step == 2 && moodOnly ? 0 : step - 1;
    notifyListeners();
  }

  void edit() {
    step = moodOnly ? 0 : 1;
    _clearMessage();
    notifyListeners();
  }

  void removePhoto(String id) {
    photos.removeWhere((p) => p.id == id);
    _inputChanged = true;
    _clearMessage();
    notifyListeners();
  }

  void clearPhotos() {
    photos = [];
    _inputChanged = true;
    _clearMessage();
    notifyListeners();
  }

  Future<void> pickPhotos({required bool camera}) async {
    if (_picking || photos.length >= 8 || progress != null) return;
    _picking = true;
    _clearMessage();
    try {
      final p = platform;
      final max = 8 - photos.length;
      final picked = p is NativeImportPlatform
          ? await p.pickCreatePhotos(camera: camera, maxCount: max)
          : await p.pickPhotos(camera: camera, maxCount: max);
      if (_disposed) return;
      photos = [...photos, ...picked.photos.take(max)];
      if (picked.photos.isNotEmpty) _inputChanged = true;
      if (picked.errors.isNotEmpty) error = picked.errors.join('\n');
    } catch (_) {
      if (!_disposed) error = 'Could not open those photos. Try again.';
    } finally {
      _picking = false;
      if (!_disposed) notifyListeners();
    }
  }

  void cancel() {
    final replacing = progressAction == 'more';
    _epoch++;
    arrivingIdeas = null;
    progress = null;
    progressAction = null;
    _clearMessage();
    if (replacing && ideas.isNotEmpty) notice = _batchNotice(ideas.length);
    unawaited(platform.cancel().catchError((Object _) {}));
    if (!_disposed) notifyListeners();
  }

  void _check(int epoch) {
    if (_disposed || epoch != _epoch) throw const _Cancelled();
  }

  Future<T?> _run<T>(
    String actionName,
    String label,
    Future<T> Function(int) action,
  ) async {
    if (progress != null) return null;
    final epoch = ++_epoch;
    _clearMessage();
    progressAction = actionName;
    progress = label;
    notifyListeners();
    try {
      final saved = await platform.settings();
      _check(epoch);
      if (!saved.hasKey) {
        needsKey = true;
        throw const _CreateError('Add a Gemini key to use Smart Create.');
      }
      final result = await action(epoch);
      _check(epoch);
      await onSuccessFlash?.call();
      _check(epoch);
      return result;
    } on _Cancelled {
      return null;
    } catch (e) {
      if (epoch == _epoch && !_disposed) {
        arrivingIdeas = null;
        error = switch (e) {
          _CreateError(:final message) => message,
          AvoidedRecipe() => 'This recipe contains a food on your avoid list. Choose another idea or try again.',
          FormatException() => 'Gemini could not make a result that follows your ingredients and options. Try again.',
          _ =>
            'Could not finish this step. Check your connection and try again.',
        };
      }
      return null;
    } finally {
      if (epoch == _epoch && !_disposed) {
        progress = null;
        progressAction = null;
        notifyListeners();
      }
    }
  }

  Future<T> _request<T>(
    int epoch,
    String stage,
    String model,
    String thinking,
    Json input,
    FutureOr<T> Function(Json) validate, {
    List<String> images = const [],
    List<String>? checks,
    FutureOr<T> Function(Json, List<String>)? reviewWithWarnings,
    bool allowModelSwitch = true,
  }) async {
    final step = switch (stage) {
      'photos' => CreateStep.photo,
      'ideas' => CreateStep.ideas,
      _ => CreateStep.recipe,
    };
    final log = AiImportDiagnostic(mode: stage, model: model);
    String? problem;
    (String, String)? fallback;
    for (var attempt = 0; attempt < 2; attempt++) {
      _check(epoch);
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(
            createRequest(
              stage,
              model,
              thinking,
              input,
              images: images,
              problem: problem,
            ),
          ),
        ),
      );
      if (attempt > 0) _phase('Double-checking…');
      if (bytes.length >= 16 * 1024 * 1024) {
        throw const _CreateError(
          'These photos are too large together. Remove a photo and try again.',
        );
      }
      log.request(bytes);
      try {
        final reply = await platform.providerRequest(bytes);
        _check(epoch);
        log.reply(reply.status, reply.bytes);
        if (reply.status < 200 || reply.status >= 300) {
          final errorBody = _providerProblem(reply.bytes);
          final paidModel = const {
            'gemini-4-argon',
            'gemini-3.1-pro-preview',
          }.contains(model);
          if (paidModel &&
              preferences.modelFor(step) == model &&
              const {400, 402, 403, 429}.contains(reply.status) &&
              RegExp(
                r'billing (?:must|needs? to|is (?:not|disabled|required))|billing_disabled|(?:enable|requires?) billing|paid[_ -](?:key|plan|tier)|free[_ -]?tier.{0,120}(?:limit.{0,9}\b0\b|not (?:available|supported))',
                dotAll: true,
              ).hasMatch(errorBody)) {
            _paidStep = step;
            throw const _CreateError(
              'This model needs a paid Gemini API key. You can use Flash with your current key.',
            );
          }
          if (reply.status == 404 &&
              allowModelSwitch &&
              model != CreatePreferences.suggestedModel &&
              preferences.modelFor(step) == model &&
              RegExp(
                r'\bmodels?\b.{0,180}(?:not found|not available|unavailable|does not exist|no longer|retired|has been removed|not supported)|(?:unknown|unavailable|unsupported|could not find) model',
                dotAll: true,
              ).hasMatch(errorBody)) {
            local.setCreatePreferences(
              preferences.withRetiredModel(step, model),
            );
            _phase('Double-checking…');
            fallback = (
              preferences.modelFor(step),
              preferences.thinkingFor(step),
            );
            break;
          }
          throw _CreateError(switch (reply.status) {
            401 || 403 => 'Google did not accept the key or model. Check your Gemini settings.',
            429 => 'Gemini reached its request limit. Try again later.',
            404 => 'This Gemini model is unavailable. Choose another in Smart Create settings.',
            _ =>
              'Gemini could not finish this request (HTTP ${reply.status}). Try again.',
          });
        }
        if (reply.bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Response too large.');
        }
        final decoded = jsonDecode(utf8.decode(reply.bytes));
        if (decoded is! Json) {
          throw const FormatException('Invalid response object.');
        }
        final raw = readCreateOutput(decoded);
        _phase('Double-checking…');
        final issues = <String>[];
        final result = attempt == 1 && reviewWithWarnings != null
            ? await reviewWithWarnings(raw, issues)
            : await validate(raw);
        _check(epoch);
        if (issues.isNotEmpty) {
          recipeWarning = issues.take(2).join(' ');
          log.value['reviewWarnings'] = issues;
        }
        _check(epoch);
        log.validation('Accepted');
        return result;
      } on FormatException catch (e) {
        problem = e.message;
        log.validation(problem);
        if (attempt == 1) rethrow;
      } on _CreateError catch (e) {
        log.validation(e.message);
        rethrow;
      } finally {
        if (epoch == _epoch && !_disposed) {
          if (checks != null) {
            log.value['checks'] = checks.map(redactImportDiagnostic).toList();
          }
          try {
            await _diagnostics.write(log.value);
          } catch (_) {
            /* Diagnostics are optional. */
          }
        }
      }
    }
    // Finish logging the retired model before the replacement starts. Its
    // validation retries and final diagnostic belong to that model alone.
    if (fallback != null) {
      return _request(
        epoch,
        stage,
        fallback.$1,
        fallback.$2,
        input,
        validate,
        images: images,
        checks: checks,
        reviewWithWarnings: reviewWithWarnings,
        allowModelSwitch: false,
      );
    }
    throw const FormatException('Invalid response.');
  }

  Future<void> next() async {
    if (progress != null) return;
    final typedItems = splitTyped(typed);
    if (typedItems.isEmpty && photos.isEmpty) {
      if (!moodOnly) return;
      // Discard the checked kitchen, including manually added ingredients.
      if (_checked || _inputChanged) {
        _lastTyped = [];
        _lastPhoto = [];
        ingredients = [];
        maybe = [];
        useFirst = {};
        _checked = false;
        _inputChanged = false;
        _invalidate();
      }
      await getIdeas();
      return;
    }
    if (_checked && !_inputChanged) {
      step = 1;
      _clearMessage();
      notifyListeners();
      return;
    }
    final oldSelected = useFirst.toSet();
    final previousTyped = _lastTyped, previousPhoto = _lastPhoto;
    final manuallyAdded = ingredients
        .where((s) => !previousTyped.contains(s) && !previousPhoto.contains(s))
        .toList();
    var found = <String>[], uncertain = <String>[];
    _clearMessage();
    if (photos.isNotEmpty) {
      final result = await _run(
        'photos',
        'Looking through your photos…',
        (epoch) => _request(
          epoch,
          'photos',
          preferences.photoModel,
          preferences.photoThinking,
          {'typed': typedItems, 'staples': preferences.staples},
          (j) => validatePhotos(j, typedItems, preferences.staples),
          images: photos.map((p) => base64Encode(p.jpeg)).toList(),
        ),
      );
      if (result == null || _disposed) return;
      found = result.found;
      uncertain = result.maybe;
    }
    _lastTyped = typedItems;
    _lastPhoto = found;
    ingredients = distinctFoods([...typedItems, ...found, ...manuallyAdded]);
    maybe = uncertain
        .where((s) => !ingredients.any((v) => sameFood(s, v)))
        .toList();
    useFirst = oldSelected.intersection(ingredients.toSet());
    _invalidate();
    _checked = true;
    _inputChanged = false;
    step = 1;
    if (photos.isNotEmpty && found.isEmpty && maybe.isEmpty) {
      notice =
          'No new food found in the photos. You can add ingredients by hand.';
    }
    notifyListeners();
  }

  List<String> _lastTyped = [], _lastPhoto = [];
  CreateKitchen get _kitchen => CreateKitchen(
    ingredients: List.of(ingredients),
    staples: preferences.staples,
    useFirst: Set.of(useFirst),
    avoid: preferences.avoid,
    otherPreferences: preferences.otherPreferences,
    meal: meal,
    effort: effort,
    servings: servings,
    mood: mood.trim(),
    extraIngredients: preferences.extraIngredients,
  );
  String? _batchNotice(int count) {
    if (count >= 4) return null;
    final suggestion = moodOnly
        ? 'Try changing your mood.'
        : 'Try adding a few more ingredients.';
    if (count == 0) {
      return ideas.isEmpty
          ? 'No ideas fit yet. $suggestion'
          : 'No more ideas fit yet. $suggestion';
    }
    return 'Only $count new ${count == 1 ? 'idea fits' : 'ideas fit'}. $suggestion';
  }

  Future<void> getIdeas({bool more = false}) async {
    if ((ingredients.isEmpty && !moodOnly) || progress != null) return;
    final kitchen = _kitchen, key = jsonEncode(_kitchen.input);
    if (!more && ideas.isNotEmpty && key == _ideaInput) {
      step = 2;
      _clearMessage();
      notice = _batchNotice(ideas.length);
      notifyListeners();
      return;
    }
    _shownIdeaTitles.addAll(ideas.map((idea) => idea.title));
    final batch = await _run(
      more ? 'more' : 'ideas',
      more ? 'Coming up with new ideas…' : 'Coming up with ideas…',
      (epoch) async {
        var fresh = <CreateIdea>[];
        final checks = <String>[];
        var count = 6;
        for (var pass = 0; pass < 2; pass++) {
          final previous = [..._shownIdeaTitles, ...fresh.map((i) => i.title)];
          final ready = fresh.where((idea) => idea.missing.isEmpty).length;
          var suppliedFullBatch = false;
          late final List<CreateIdea> next;
          try {
            next = await _request(
              epoch,
              'ideas',
              preferences.ideaModel,
              preferences.ideaThinking,
              {
                ...kitchen.input,
                'count': count,
                'previousTitles': previous,
                if (pass > 0) 'alreadyReady': ready,
                if (pass > 0) 'alreadyShopping': fresh.length - ready,
              },
              (j) {
                suppliedFullBatch =
                    j['ideas'] is List && (j['ideas'] as List).length >= 6;
                return validateIdeas(
                  j,
                  kitchen,
                  previous,
                  checks,
                  limit: count,
                  readySlots: kitchen.moodOnly ? 4 : 4 - ready,
                );
              },
              checks: checks,
            );
          } catch (_) {
            _check(epoch);
            if (fresh.length < 4) rethrow;
            // This call only improved the mix. Keep the usable first reply
            // when the provider cannot supply the remaining slots.
            _paidStep = null;
            break;
          }
          fresh = selectIdeaBatch([...fresh, ...next], kitchen);
          count = 6 - fresh.length;
          if (fresh.length < 4) continue;
          if (!kitchen.moodOnly && suppliedFullBatch) {
            final readyCount = fresh
                .where((idea) => idea.missing.isEmpty)
                .length;
            final shoppingCount = fresh.length - readyCount;
            if (shoppingCount < 2) continue;
            if (fresh.length == 6 && readyCount < 3) {
              count = 3 - readyCount;
              continue;
            }
          }
          break;
        }
        _check(epoch);
        if (more && fresh.isNotEmpty) {
          arrivingIdeas = fresh;
          notice = _batchNotice(fresh.length);
          _shownIdeaTitles.addAll(fresh.map((idea) => idea.title));
          notifyListeners();
        }
        return fresh;
      },
    );
    if (batch == null || _disposed) return;
    arrivingIdeas = null;
    if (!more || batch.isNotEmpty) {
      ideas = batch;
      _ideaBatchRevision++;
    }
    _shownIdeaTitles.addAll(batch.map((idea) => idea.title));
    _ideaInput = key;
    step = 2;
    notice = _batchNotice(batch.length);
    notifyListeners();
  }

  Future<Candidate?> recipe(CreateIdea idea) async {
    if (progress != null) return null;
    final k = _kitchen;
    int? writtenMinutes;
    recipeWarning = null;
    reviewIdeaTitle = idea.title;
    Future<Candidate> candidate(Json raw, [List<String>? warnings]) async {
      final written = validateRecipe(raw, k, idea, warnings: warnings);
      try {
        final result = await smartCreateCandidate(written: jsonEncode(written));
        writtenMinutes = createTotalMinutes(written['totalTime'] as String);
        return result;
      } on ServiceError catch (e) {
        throw FormatException(e.message);
      }
    }

    final result = await _run(
      'recipe',
      'Writing your recipe…',
      (epoch) => _request(
        epoch,
        'recipe',
        preferences.recipeModel,
        preferences.recipeThinking,
        k.recipeRequestInput(
          idea,
          existingTags: existingTags?.call() ?? const [],
        ),
        (raw) => candidate(raw),
        reviewWithWarnings: candidate,
      ),
    );
    final minutes = writtenMinutes;
    if (result != null &&
        !_disposed &&
        minutes != null &&
        minutes != idea.minutes &&
        ideas.contains(idea)) {
      ideas = [
        for (final current in ideas)
          if (current == idea) current.withMinutes(minutes) else current,
      ];
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    local.removeListener(_settingsChanged);
    if (progress != null) {
      unawaited(platform.cancel().catchError((Object _) {}));
    }
    super.dispose();
  }
}
