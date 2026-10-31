import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../library_catalog.dart';
import '../local_preferences.dart';
import '../name_matching.dart';
import '../recipe_store.dart';
import 'components.dart';
import 'feedback.dart';
import 'navigation_feedback.dart';
import 'pixel_scroll.dart';
import 'recipe_filters.dart';

/// A tag exists only after this flow commits it to at least one recipe.
Future<String?> addTagToRecipes(
  BuildContext context,
  RecipeStore store, {
  String? tag,
  Set<String>? recipeIds,
}) async {
  tag ??= await showDialog<String>(
    context: context,
    builder: (_) => _TagNameDialog(
      catalog: LibraryCatalog(store.summaries, LibraryKind.tags),
      choosingRecipes: recipeIds == null,
    ),
  );
  if (tag == null || !context.mounted) return null;
  if (recipeIds != null) {
    return _confirmAddition(context, store, tag, recipeIds);
  }
  return Navigator.of(context).push<String>(
    cookdexRoute<String>(
      context,
      builder: (_) => _TagRecipePicker(store: store, tag: tag!),
    ),
  );
}

Future<String?> _confirmAddition(
  BuildContext context,
  RecipeStore store,
  String tag,
  Set<String> ids,
) async {
  final target =
      LibraryCatalog(
        store.summaries,
        LibraryKind.tags,
      ).matchingTag(tag)?.name ??
      tag;
  final changing = store.summaries
      .where((r) => ids.contains(r.id) && !r.tags.contains(target))
      .map((r) => r.id)
      .toList();
  if (changing.isEmpty) {
    showFeedback(context, 'These recipes already have “$target”.');
    return null;
  }
  final generation = store.generation;
  if (!await confirmCookdex(
        context,
        title: 'Add tag?',
        action: 'Add',
        content: Text('Add “$target” to ${recipeCount(changing.length)}?'),
      ) ||
      !context.mounted) {
    return null;
  }
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  final progress = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('Adding tag'),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Expanded(child: Text('Saving your changes…')),
          ],
        ),
      ),
    ),
  );
  navigator.push(progress);
  try {
    final result = await store.addLibraryTag(generation, changing, target);
    if (progress.isActive) navigator.removeRoute(progress);
    showFeedbackWithMessenger(
      messenger,
      'Added “$target” to ${recipeCount(result.count)}',
      duration: const Duration(seconds: 10),
      onUndo: () async {
        try {
          await store.undoLibraryNames(result.undo);
          showFeedbackWithMessenger(
            messenger,
            'Undone in ${recipeCount(result.count)}',
          );
        } catch (_) {
          showFeedbackWithMessenger(
            messenger,
            'Could not undo. The recipes may have changed.',
            kind: FeedbackKind.error,
          );
        }
      },
    );
    return target;
  } catch (_) {
    showFeedbackWithMessenger(
      messenger,
      'Could not add tag. Nothing changed. Review the recipes and try again.',
      kind: FeedbackKind.error,
    );
    return null;
  } finally {
    if (progress.isActive) navigator.removeRoute(progress);
  }
}

class _TagNameDialog extends StatefulWidget {
  const _TagNameDialog({required this.catalog, required this.choosingRecipes});
  final LibraryCatalog catalog;
  final bool choosingRecipes;
  @override
  State<_TagNameDialog> createState() => _TagNameDialogState();
}

class _TagNameDialogState extends State<_TagNameDialog> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = normalizeNameWhitespace(_text.text);
    final match = value.isEmpty ? null : widget.catalog.matchingTag(value);
    final suggestions = widget.catalog.names
        .where((n) => n.name.toLowerCase().contains(value.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text(widget.choosingRecipes ? 'New tag' : 'Add tag'),
      content: SizedBox(
        width: 420,
        child: PixelSingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogFieldPadding(
                child: TextField(
                  controller: _text,
                  autofocus: false,
                  decoration: const InputDecoration(labelText: 'Tag name'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                match == null
                    ? (widget.choosingRecipes
                          ? 'Choose recipes next to create this tag.'
                          : 'Choose an existing tag or enter a new name.')
                    : 'This matches “${match.name}” (${recipeCount(match.count)}), so that spelling will be used.',
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Existing tags',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                SizedBox(
                  height: (suggestions.length * 56.0).clamp(56, 224),
                  child: PixelListView.builder(
                    itemCount: suggestions.length,
                    itemBuilder: (context, i) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Align(
                        alignment: Alignment.centerLeft,
                        child: TonalTag(suggestions[i].name),
                      ),
                      trailing: Text('${suggestions[i].count}'),
                      onTap: () => setState(() {
                        _text.text = suggestions[i].name;
                        _text.selection = TextSelection.collapsed(
                          offset: _text.text.length,
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: value.isEmpty
              ? null
              : () => Navigator.pop(context, match?.name ?? value),
          child: Text(widget.choosingRecipes ? 'Choose recipes' : 'Continue'),
        ),
      ],
    );
  }
}

class _TagRecipePicker extends StatefulWidget {
  const _TagRecipePicker({required this.store, required this.tag});
  final RecipeStore store;
  final String tag;
  @override
  State<_TagRecipePicker> createState() => _TagRecipePickerState();
}

class _TagRecipePickerState extends State<_TagRecipePicker> {
  late final LocalPreferences _filters = LocalPreferences.memory()
    ..query = widget.store.preferences.query
    ..searchFields = Set.of(widget.store.preferences.searchFields)
    ..sort = widget.store.preferences.sort
    ..favoritesOnly = widget.store.preferences.favoritesOnly;
  late final _query = TextEditingController(text: _filters.query);
  final Set<String> _selected = {};
  bool _busy = false;
  @override
  void dispose() {
    _query.dispose();
    _filters.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    setState(() => _busy = true);
    final result = await _confirmAddition(
      context,
      widget.store,
      widget.tag,
      _selected,
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, result);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.store, _filters]),
    builder: (context, _) {
      if (_query.text != _filters.query) _query.text = _filters.query;
      final all = widget.store.summaries;
      final locked = all
          .where((r) => r.tags.contains(widget.tag))
          .map((r) => r.id)
          .toSet();
      final existing = all.map((r) => r.id).toSet();
      _selected.removeWhere(
        (id) => locked.contains(id) || !existing.contains(id),
      );
      final matches = widget.store.recipesMatching(_filters);
      final selectable = matches.where((r) => !locked.contains(r.id)).toList();
      final matchingLocked = matches.length - selectable.length;
      return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(title: const Text('Choose recipes')),
          body: SafeArea(
            top: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Text(
                    'Add “${widget.tag}” to recipes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _query,
                    onChanged: _filters.setQuery,
                    decoration: InputDecoration(
                      hintText: 'Search recipes',
                      prefixIcon: const Icon(Symbols.search),
                      suffixIcon: SearchFieldActions(
                        controller: _query,
                        onClear: () => _filters.setQuery(''),
                        onOptions: () =>
                            showRecipeSearchFields(context, _filters),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilterChip(
                        label: const Text('Favorites'),
                        avatar: Icon(
                          Symbols.star,
                          size: 18,
                          fill: _filters.favoritesOnly ? 1 : 0,
                        ),
                        selected: _filters.favoritesOnly,
                        showCheckmark: false,
                        selectedColor: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        onSelected: _filters.setFavoritesOnly,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_selected.length} selected',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy || selectable.isEmpty
                            ? null
                            : () => setState(() {
                                _selected.clear();
                                _selected.addAll(
                                  matches
                                      .where((r) => !locked.contains(r.id))
                                      .map((r) => r.id),
                                );
                              }),
                        child: Text('Select all (${selectable.length})'),
                      ),
                    ],
                  ),
                ),
                if (matchingLocked > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '$matchingLocked already tagged · checked and locked',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  child: matches.isEmpty
                      ? const Center(child: Text('No matching recipes'))
                      : PixelListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, i) {
                            final recipe = matches[i];
                            final hasTag = locked.contains(recipe.id);
                            return CheckboxListTile(
                              key: ValueKey(('tag-recipe', recipe.id)),
                              controlAffinity: ListTileControlAffinity.leading,
                              value: hasTag || _selected.contains(recipe.id),
                              onChanged: hasTag || _busy
                                  ? null
                                  : (checked) => setState(() {
                                      checked!
                                          ? _selected.add(recipe.id)
                                          : _selected.remove(recipe.id);
                                    }),
                              title: Text(recipe.title),
                              subtitle: hasTag
                                  ? Text('Already has “${widget.tag}”')
                                  : recipe.tags.isEmpty
                                  ? null
                                  : Text(recipe.tags.join(' · ')),
                              secondary: hasTag
                                  ? const Icon(Symbols.lock, size: 20)
                                  : recipe.favorite
                                  ? const Icon(Symbols.star, fill: 1, size: 20)
                                  : null,
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: _busy || _selected.isEmpty ? null : _add,
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
