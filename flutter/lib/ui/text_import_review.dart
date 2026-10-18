import 'dart:convert';

import 'package:flutter/material.dart';

import '../editor_controller.dart';
import '../editor_model.dart';
import '../import_service.dart';
import '../name_matching.dart';
import '../recipe_store.dart';
import '../src/rust/api.dart' as core;
import 'components.dart';
import 'pixel_scroll.dart';
import 'recipe_editor.dart';

/// Content comparison deliberately excludes identity, favorites and history.
bool sameTextRecipe(core.Recipe a, core.Recipe b) =>
    jsonEncode(recipeToJson(a)['fields']) ==
    jsonEncode(recipeToJson(b)['fields']);

List<NameMatch> textImportNameMatches(
  Iterable<core.RecipeFields> fields,
  List<core.RecipeSummary> library,
) {
  Map<String, String> preferred(bool tags) => {
    for (final suggestion in groupNameSuggestions([
      for (final recipe in library)
        for (final name in tags ? recipe.tags : recipe.ingredients)
          NameObservation(
            name: name,
            recipeId: recipe.id,
            updatedAt: recipe.updatedAt,
          ),
    ]))
      suggestion.key: suggestion.name,
  };
  final ingredients = preferred(false), tags = preferred(true);
  final matches = <NameMatch>[];
  final seen = <(bool, String, String)>{};
  for (final recipe in fields) {
    for (final tag in [false, true]) {
      final names = tag ? recipe.tags : recipe.ingredients.map((i) => i.name);
      for (final raw in names) {
        final name = normalizeNameWhitespace(raw);
        final replacement = (tag ? tags : ingredients)[sameNameKey(name)];
        if (replacement != null &&
            replacement != name &&
            seen.add((tag, name, replacement))) {
          matches.add(NameMatch(matches.length, tag, name, replacement));
        }
      }
    }
  }
  return matches;
}

/// Only consented spellings change; even whitespace and tag order otherwise stay.
core.RecipeFields applyTextImportNames(
  core.RecipeFields fields,
  List<NameMatch> matches,
  Set<int> accepted,
) {
  if (accepted.isEmpty) return fields;
  String name(String raw, bool tag) {
    for (final index in accepted) {
      final match = matches[index];
      if (match.tag == tag && match.entered == normalizeNameWhitespace(raw)) {
        return match.preferred;
      }
    }
    return raw;
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
    tags: fields.tags.map((t) => name(t, true)).toList(),
    ingredients: [
      for (final i in fields.ingredients)
        core.Ingredient(
          amount: i.amount,
          unit: i.unit,
          name: name(i.name, false),
          prepNote: i.prepNote,
          optional: i.optional,
          section: i.section,
        ),
    ],
  );
}

class TextImportReview extends StatefulWidget {
  const TextImportReview({
    super.key,
    required this.blocks,
    required this.store,
    required this.service,
    required this.onReview,
  });
  final List<TextImportBlock> blocks;
  final RecipeStore store;
  final ImportService service;
  final Future<core.Recipe?> Function(BuildContext, core.Candidate) onReview;
  @override
  State<TextImportReview> createState() => _TextImportReviewState();
}

class _TextImportReviewState extends State<TextImportReview> {
  final _selected = <int>{};
  final _exact = <int>{};
  final _sameName = <int>{};
  final _saved = <int, core.Recipe>{};
  bool _loading = true, _saving = false, _smart = false;
  int _epoch = 0, _generation = -1;
  String? _error;
  core.Recipe? _lastSaved;
  bool get _busy => _loading || _saving || _smart;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final generation = widget.store.generation;
      final library = <core.Recipe>[];
      for (final summary in List.of(widget.store.summaries)) {
        final recipe = await widget.store.repository.detail(summary.id);
        if (!mounted || epoch != _epoch) return;
        if (recipe != null) library.add(recipe);
      }
      if (generation != widget.store.generation) {
        throw StateError('Your library changed. Check again before importing.');
      }
      _exact.clear();
      _sameName.clear();
      _selected.clear();
      for (final (index, block) in widget.blocks.indexed) {
        final recipe = block.candidate?.recipe;
        if (recipe == null || _saved.containsKey(index)) continue;
        if (library.any((r) => sameTextRecipe(r, recipe))) {
          _exact.add(index);
        } else {
          _selected.add(index);
          if (library.any(
            (r) =>
                normalizeDuplicateTitle(r.fields.title) ==
                normalizeDuplicateTitle(recipe.fields.title),
          )) {
            _sameName.add(index);
          }
        }
      }
      _generation = generation;
    } catch (_) {
      _generation = -1;
      _error = 'Could not check your library. Try again before importing.';
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy || _selected.isEmpty) return;
    if (_generation != widget.store.generation) {
      await _refresh();
      if (mounted) {
        setState(
          () => _error =
              'Your library changed. Review the selection and import again.',
        );
      }
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var generation = _generation;
      final selected = _selected.toList()..sort();
      final matches = textImportNameMatches(
        selected.map((i) => widget.blocks[i].candidate!.recipe.fields),
        widget.store.summaries,
      );
      final accepted = matches.isEmpty
          ? <int>{}
          : await showDialog<Set<int>>(
              context: context,
              builder: (_) => NameMatchReview(matches: matches),
            );
      if (!mounted || accepted == null) return;
      for (final index in selected) {
        if (widget.store.generation != generation) {
          throw StateError(
            'Your library changed. Check it again before continuing.',
          );
        }
        final saved = await widget.store.importRecipe(
          generation: generation,
          fields: applyTextImportNames(
            widget.blocks[index].candidate!.recipe.fields,
            matches,
            accepted,
          ),
          choice: const core.DuplicateChoice.keepBoth(),
        );
        _saved[index] = saved;
        _lastSaved = saved;
        _selected.remove(index);
        generation = widget.store.generation;
        _generation = generation;
        if (!mounted) return;
      }
      if (mounted) Navigator.pop(context, _lastSaved);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _saved.isEmpty
              ? 'Could not import the recipes. Check your library and try again.'
              : '${_saved.length} imported. The remaining recipes could not be imported. Saved recipes will not be added again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _smartImport(int index) async {
    final epoch = ++_epoch;
    setState(() {
      _smart = true;
      _error = null;
    });
    try {
      final discovery = await widget.service.smartText(
        widget.blocks[index].text,
      );
      if (!mounted || epoch != _epoch) return;
      if (discovery.candidates.isEmpty) throw StateError('No recipe found');
      final candidate = await widget.service.select(discovery, 0);
      if (!mounted || epoch != _epoch) return;
      final saved = await widget.onReview(context, candidate);
      if (!mounted || epoch != _epoch) return;
      if (saved != null) {
        _saved[index] = saved;
        _lastSaved = saved;
      }
      setState(() => _smart = false);
      await _refresh();
    } on ImportCancelled {
      // Explicit cancellation leaves the original block available.
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(
          () => _error = 'Smart Import could not read this recipe. Check Smart Import settings and try again.',
        );
      }
    } finally {
      if (mounted && epoch == _epoch) setState(() => _smart = false);
    }
  }

  void _cancelSmart() {
    _epoch++;
    widget.service.cancel();
    setState(() => _smart = false);
  }

  @override
  void dispose() {
    _epoch++;
    if (_smart) widget.service.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<core.Recipe>(
    canPop: !_saving,
    child: CookdexFormScaffold(
      title: 'Import recipes',
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: PixelListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Choose the recipes to add to your library.'),
              const SizedBox(height: 12),
              if (_loading) const LinearProgressIndicator(),
              for (final (index, block) in widget.blocks.indexed)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: _saved.containsKey(index)
                        ? ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(_saved[index]!.fields.title),
                            subtitle: const Text('Imported'),
                          )
                        : block.candidate == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Couldn't read this one",
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text('Recipe ${index + 1}'),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _smartImport(index),
                                child: const Text('Try Smart Import'),
                              ),
                            ],
                          )
                        : CheckboxListTile(
                            key: ValueKey('text-import-$index'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _selected.contains(index),
                            onChanged: _busy || _generation < 0
                                ? null
                                : (checked) => setState(() {
                                    if (checked == true) {
                                      _selected.add(index);
                                    } else {
                                      _selected.remove(index);
                                    }
                                  }),
                            title: Text(block.candidate!.recipe.fields.title),
                            subtitle: _exact.contains(index)
                                ? const Text('Already in your library')
                                : _sameName.contains(index)
                                ? const Text('Same name as one you have')
                                : null,
                          ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Check library again'),
                ),
              ],
              const SizedBox(height: 16),
              if (_saving || _smart) const LinearProgressIndicator(),
              if (_smart)
                TextButton(
                  onPressed: _cancelSmart,
                  child: const Text('Cancel'),
                ),
              FilledButton(
                onPressed: _busy || _generation < 0 || _selected.isEmpty
                    ? null
                    : _save,
                child: Text('Import selected (${_selected.length})'),
              ),
              if (_lastSaved != null)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.pop(context, _lastSaved),
                  child: const Text('Done'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
