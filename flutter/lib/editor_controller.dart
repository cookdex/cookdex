import 'dart:async';
import 'dart:convert';
import 'dart:developer' as timeline;

import 'package:flutter/foundation.dart';

import 'draft_storage.dart';
import 'editor_model.dart';
import 'name_matching.dart';
import 'recipe_store.dart';
import 'src/rust/api.dart' as core;

class EditorController extends ChangeNotifier {
  EditorController._(
    this.store,
    this.storage,
    this.draft, {
    required this.recovered,
  }) {
    _baseline = jsonEncode(draft.toJson());
    dirty = recovered;
  }
  final RecipeStore store;
  final DraftStorage storage;
  final EditorDraft draft;
  final bool recovered;
  late final String _baseline;
  bool dirty = false, saving = false, _disposed = false, _finished = false;
  String? persistenceError;
  int version = 0;
  Future<void> _writes = Future.value();
  Timer? _debounce;
  bool _pendingWrite = false;
  EditorRecipeRepository get _repository =>
      store.repository as EditorRecipeRepository;

  static Future<EditorController> create({
    required RecipeStore store,
    required DraftStorage storage,
    core.Recipe? base,
    core.Candidate? imported,
    bool exactTextImport = false,
    Map<String, dynamic>? recovered,
  }) async {
    final EditorDraft draft;
    if (recovered != null) {
      if (recovered['committed'] == true) {
        final committed = recipeFromJson(
          recovered['base'] as Map<String, dynamic>,
        );
        final current = await store.repository.detail(committed.id);
        if (current == null) {
          throw StateError(
            'The saved recipe was deleted. Discard this completed draft.',
          );
        }
        return EditorController._(
          store,
          storage,
          EditorDraft.fromRecipe(
            current,
            await store.repository.ingredientAmounts(
              current.fields.ingredients,
            ),
          ),
          recovered: false,
        );
      }
      draft = EditorDraft.fromJson(recovered);
      final original = draft.base;
      if (original != null) {
        final current = await store.repository.detail(original.id);
        if (current == null ||
            jsonEncode(recipeToJson(current)) !=
                jsonEncode(recipeToJson(original))) {
          draft.stale = true;
          // Older drafts stored only text. Clear the core's exact stale error
          // only when recovery confirms that the copy banner applies.
          if (draft.error == 'The collection changed. Refresh before saving.') {
            draft.error = null;
          }
        }
      }
    } else if (imported != null) {
      draft = EditorDraft.fromRecipe(
        imported.recipe,
        await store.repository.ingredientAmounts(
          imported.recipe.fields.ingredients,
        ),
      );
      draft.base = null;
      draft.imported = true;
      draft.exactTextImport = exactTextImport;
      if (exactTextImport && imported.recipe.fields.steps.isEmpty) {
        draft.steps.clear();
      }
      draft.importWarnings.addAll(imported.warnings);
      final review = imported.aiReview;
      if (review != null) {
        draft.aiGuessedFields.addAll(review.guessedFields);
        for (final index in review.guessedSteps) {
          if (index < draft.steps.length) draft.steps[index].aiGuess = true;
        }
      }
    } else if (base != null) {
      draft = EditorDraft.fromRecipe(
        base,
        await store.repository.ingredientAmounts(base.fields.ingredients),
      );
    } else {
      draft = EditorDraft();
    }
    final controller = EditorController._(
      store,
      storage,
      draft,
      recovered: recovered != null,
    );
    if (imported != null) {
      controller.dirty = true;
      controller._persist();
    }
    return controller;
  }

  void changed({bool clearError = true, bool structural = true}) {
    if (_finished || _disposed) return;
    version++;
    final hadError = draft.error != null;
    if (clearError) draft.error = null;
    dirty =
        true; // Conservative until the debounced snapshot or explicit flush.
    _pendingWrite = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _persist);
    if (structural || hadError) notifyListeners();
  }

  void _persist() {
    _debounce?.cancel();
    _pendingWrite = false;
    // Snapshot now, so queued writes cannot observe later mutable form values.
    final encoded = timeline.Timeline.timeSync(
      'editor.draft.encode',
      () => jsonEncode(draft.toJson()),
    );
    if (!_finished) dirty = draft.imported || recovered || encoded != _baseline;
    final target = storage;
    final snapshot = target is EncodedDraftStorage
        ? null
        : jsonDecode(encoded) as Map<String, dynamic>;
    _writes = _writes.then((_) async {
      try {
        if (target is EncodedDraftStorage) {
          await (target as EncodedDraftStorage).writeEncoded(encoded);
        } else {
          await target.write(snapshot!);
        }
        if (persistenceError != null) {
          persistenceError = null;
          if (!_disposed) notifyListeners();
        }
      } catch (_) {
        persistenceError = 'Could not save the local draft.';
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> flush() {
    if (_pendingWrite) _persist();
    return _writes;
  }

  void addTag(String value, Iterable<String> suggestions) {
    final entered = normalizeNameWhitespace(value);
    if (entered.isEmpty) return;
    if (!draft.tags.contains(entered)) {
      draft.tags.add(entered);
    }
    draft.tagInput = '';
    changed();
  }

  Future<List<core.PastedIngredient>> previewIngredients(
    String text,
    String section,
  ) => _repository.parseIngredientPaste(text, section);

  Future<void> applyIngredients(
    List<core.PastedIngredient> parsed,
    EditableSection target,
  ) async {
    final inputVersion = version;
    final formatted = await store.repository.ingredientAmounts(
      parsed.map((p) => p.ingredient).toList(),
    );
    if (_disposed ||
        version != inputVersion ||
        !draft.sections.contains(target)) {
      return;
    }
    var section = target;
    for (var i = 0; i < parsed.length; i++) {
      final ingredient = parsed[i].ingredient;
      if (ingredient.section != section.name) {
        final previous = section;
        section =
            draft.sections
                .where((s) => s.name == ingredient.section)
                .firstOrNull ??
            EditableSection(name: ingredient.section);
        if (!draft.sections.contains(section)) {
          draft.sections.insert(draft.sections.indexOf(previous) + 1, section);
        }
      }
      section.rows.removeWhere((r) => r.blank);
      section.rows.add(
        EditableIngredient(
          amount: formatted[i],
          unit: ingredient.unit,
          name: ingredient.name,
          prepNote: ingredient.prepNote,
          optional: ingredient.optional,
          originalAmount: ingredient.amount,
          originalText: formatted[i],
          originalUnit: ingredient.unit,
          showNote: ingredient.prepNote.isNotEmpty,
        ),
      );
    }
    clearPaste();
  }

  void applySteps(List<String> steps) {
    draft.steps.removeWhere((s) => s.text.trim().isEmpty);
    draft.steps.addAll(steps.map(EditableStep.new));
    clearPaste();
  }

  void clearPaste() {
    draft.pasteText = '';
    draft.pasteKind = null;
    draft.pasteSectionId = null;
    changed();
  }

  void reorder<T>(List<T> rows, int oldIndex, int newIndex) {
    final row = rows.removeAt(oldIndex);
    rows.insert(newIndex, row);
    changed();
  }

  void move<T>(List<T> rows, T row, int offset) {
    final index = rows.indexOf(row);
    final target = index + offset;
    if (index < 0 || target < 0 || target >= rows.length) return;
    rows.removeAt(index);
    rows.insert(target, row);
    changed();
  }

  VoidCallback remove<T>(List<T> rows, T row) {
    final index = rows.indexOf(row);
    rows.remove(row);
    changed();
    var restored = false;
    return () {
      if (_disposed || _finished || restored || rows.contains(row)) return;
      restored = true;
      rows.insert(index.clamp(0, rows.length), row);
      changed();
    };
  }

  Future<core.Recipe?> save({
    Future<Set<int>?> Function(List<NameMatch>)? reviewNames,
    Future<core.DuplicateChoice?> Function(List<core.RecipeSummary>)?
    chooseDuplicate,
  }) async {
    if (saving || _finished) return null;
    if (draft.unappliedPaste || draft.tagInput.trim().isNotEmpty) {
      draft.error = draft.unappliedPaste
          ? 'Apply or discard the pasted text first.'
          : 'Add or clear the tag first.';
      changed(clearError: false);
      return null;
    }
    saving = true;
    draft.error = null;
    notifyListeners();
    try {
      final saveVersion = version;
      final generation = store.generation;
      var fields = await _repository.normalizeEditorFields(
        draft.fields(),
        draft.amountInputs(),
      );
      if (version != saveVersion) {
        throw StateError('The draft changed. Save again.');
      }
      if (draft.exactTextImport) fields = _exactFields(fields);
      final matches = nameMatches();
      if (matches.isNotEmpty) {
        final accepted = await reviewNames?.call(matches);
        if (accepted == null) return null;
        fields = await _repository.normalizeEditorFields(
          applyNameMatches(draft.fields(), matches, accepted),
          draft.amountInputs(),
        );
        if (draft.exactTextImport) {
          fields = applyNameMatches(
            _exactFields(fields),
            matches,
            accepted,
            preserve: true,
          );
        }
      } else if (!draft.exactTextImport) {
        fields = applyNameMatches(fields, const [], const {});
      }
      if (version != saveVersion || store.generation != generation) {
        throw StateError('The draft or collection changed. Save again.');
      }
      final core.Recipe result;
      if (draft.imported) {
        final duplicates = store.summaries
            .where(
              (r) =>
                  normalizeDuplicateTitle(r.title) ==
                  normalizeDuplicateTitle(fields.title),
            )
            .toList();
        core.DuplicateChoice? choice;
        if (draft.exactTextImport) {
          choice = const core.DuplicateChoice.keepBoth();
        } else if (duplicates.isNotEmpty) {
          choice = await chooseDuplicate?.call(duplicates);
          if (choice == null) return null;
        }
        if (version != saveVersion) {
          throw StateError('The draft changed. Save again.');
        }
        result = await store.importRecipe(
          generation: generation,
          fields: fields,
          choice: choice,
        );
      } else {
        result = await store.saveRecipe(
          base: draft.stale ? null : draft.base,
          fields: fields,
        );
      }
      _finished = true;
      dirty = false;
      draft.aiGuessedFields.clear();
      for (final step in draft.steps) {
        step.aiGuess = false;
      }
      await flush();
      // If removing the file fails, recovery recognizes this completed save.
      draft.base = result;
      try {
        await storage.write({...draft.toJson(), 'committed': true});
        await storage.clear();
      } catch (_) {
        persistenceError =
            'Recipe saved; the local draft could not be cleared.';
      }
      return result;
    } catch (e) {
      draft.error = e is core.ServiceError ? e.message : e.toString();
      // A changed original must be reviewed as a copy, never overwritten by retry.
      if (draft.base != null) {
        try {
          final current = await store.repository.detail(draft.base!.id);
          if (current == null ||
              jsonEncode(recipeToJson(current)) !=
                  jsonEncode(recipeToJson(draft.base!))) {
            draft.stale = true;
            // The copy banner explains this condition; retain other save errors.
            if (e is core.ServiceError && e.code == core.ErrorCode.staleWrite) {
              draft.error = null;
            }
          }
        } catch (_) {
          /* Preserve the original base while offline/unavailable. */
        }
      }
      dirty = true;
      _persist();
      return null;
    } finally {
      saving = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> discard() async {
    await flush();
    await storage.clear();
    _finished = true;
    dirty = false;
  }

  core.RecipeFields _exactFields(core.RecipeFields normalized) {
    final raw = draft.fields();
    final inputs = draft.amountInputs();
    return core.RecipeFields(
      title: raw.title,
      description: raw.description,
      servings: raw.servings,
      prepTime: raw.prepTime,
      cookTime: raw.cookTime,
      totalTime: raw.totalTime,
      source: raw.source,
      tags: raw.tags,
      notes: raw.notes,
      steps: raw.steps,
      ingredients: [
        for (final (i, row) in raw.ingredients.indexed)
          core.Ingredient(
            amount: inputs[i] == null
                ? row.amount
                : normalized.ingredients[i].amount,
            unit: row.unit,
            name: row.name,
            prepNote: row.prepNote,
            optional: row.optional,
            section: row.section,
          ),
      ],
    );
  }

  List<NameMatch> nameMatches() {
    Map<String, String> preferred(bool tags) => {
      for (final suggestion in groupNameSuggestions([
        for (final recipe in store.summaries)
          for (final name in tags ? recipe.tags : recipe.ingredients)
            NameObservation(
              name: name,
              recipeId: recipe.id,
              updatedAt: recipe.updatedAt,
            ),
      ]))
        suggestion.key: suggestion.name,
    };
    final ingredients = preferred(false);
    final tags = preferred(true);
    final matches = <NameMatch>[];
    for (final (index, entry) in draft.ingredients.indexed) {
      final row = entry.$2;
      final name = normalizeNameWhitespace(row.name);
      if (!draft.imported &&
          row.originalName != null &&
          name == normalizeNameWhitespace(row.originalName!)) {
        continue;
      }
      final replacement = ingredients[sameNameKey(name)];
      if (replacement != null && replacement != name) {
        matches.add(NameMatch(index, false, name, replacement));
      }
    }
    final originalTags = draft.imported
        ? <String>{}
        : (draft.base?.fields.tags ?? []).map(normalizeNameWhitespace).toSet();
    for (final (index, raw) in draft.tags.indexed) {
      final name = normalizeNameWhitespace(raw);
      if (originalTags.contains(name)) continue;
      final replacement = tags[sameNameKey(name)];
      if (replacement != null && replacement != name) {
        matches.add(NameMatch(index, true, name, replacement));
      }
    }
    return matches;
  }

  @override
  void dispose() {
    if (_pendingWrite && !_finished) _persist();
    _debounce?.cancel();
    _disposed = true;
    super.dispose();
  }
}

String normalizeDuplicateTitle(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class NameMatch {
  const NameMatch(this.index, this.tag, this.entered, this.preferred);
  final int index;
  final bool tag;
  final String entered, preferred;
}

core.RecipeFields applyNameMatches(
  core.RecipeFields fields,
  List<NameMatch> matches,
  Set<int> accepted, {
  bool preserve = false,
}) {
  String name(String value, int index, bool tag) {
    for (final (matchIndex, match) in matches.indexed) {
      if (match.index == index &&
          match.tag == tag &&
          accepted.contains(matchIndex)) {
        return match.preferred;
      }
    }
    return preserve ? value : normalizeNameWhitespace(value);
  }

  return core.RecipeFields(
    title: fields.title,
    description: fields.description,
    servings: fields.servings,
    prepTime: fields.prepTime,
    cookTime: fields.cookTime,
    totalTime: fields.totalTime,
    source: fields.source,
    notes: fields.notes,
    steps: fields.steps,
    tags: preserve
        ? [
            for (final (index, value) in fields.tags.indexed)
              name(value, index, true),
          ]
        : {
            for (final (index, value) in fields.tags.indexed)
              name(value, index, true),
          }.toList(),
    ingredients: [
      for (final (index, row) in fields.ingredients.indexed)
        core.Ingredient(
          amount: row.amount,
          unit: row.unit,
          name: name(row.name, index, false),
          prepNote: row.prepNote,
          optional: row.optional,
          section: row.section,
        ),
    ],
  );
}
