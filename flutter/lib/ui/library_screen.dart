import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../library_catalog.dart';
import '../name_matching.dart';
import '../recipe_store.dart';
import '../src/rust/api.dart' as core;
import 'components.dart';
import 'feedback.dart';
import 'tag_addition.dart';
import 'pixel_scroll.dart';
import 'navigation_feedback.dart';

typedef LibraryRecipeOpener = void Function(BuildContext context, String id);

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.store,
    required this.onOpenRecipe,
  });
  final RecipeStore store;
  final LibraryRecipeOpener onOpenRecipe;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  LibraryKind _kind = LibraryKind.ingredients;
  final _search = TextEditingController();
  final _scroll = PixelScrollController();
  late final _LibraryActions _actions = _LibraryActions(widget.store);
  String? _selected;
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _actions.dispose();
    super.dispose();
  }

  void _select(LibraryName name, bool wide) {
    if (wide) {
      setState(() => _selected = name.name);
      return;
    }
    Navigator.of(context).push(
      cookdexRoute<void>(
        context,
        builder: (_) => _NamePage(
          actions: _actions,
          kind: _kind,
          name: name.name,
          onOpenRecipe: widget.onOpenRecipe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _actions,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 600;
        final catalog = _actions.catalog(_kind);
        final query = _search.text.trim().toLowerCase();
        final names = catalog.names
            .where((n) => n.name.toLowerCase().contains(query))
            .toList();
        final duplicates = _actions
            .duplicates(_kind)
            .where(
              (group) => group.any((n) => n.name.toLowerCase().contains(query)),
            )
            .toList();
        final letters = <String, List<LibraryName>>{};
        for (final name in names) {
          letters.putIfAbsent(name.letter, () => []).add(name);
        }
        final list = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<LibraryKind>(
                  segments: const [
                    ButtonSegment(
                      value: LibraryKind.ingredients,
                      label: Text('Ingredients'),
                    ),
                    ButtonSegment(value: LibraryKind.tags, label: Text('Tags')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _actions.busy
                      ? null
                      : (values) => setState(() {
                          _kind = values.single;
                          _selected = null;
                          _search.clear();
                          if (_scroll.hasClients) _scroll.jumpTo(0);
                        }),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _kind == LibraryKind.tags
                      ? 'Search tags'
                      : 'Search ingredients',
                  prefixIcon: const Icon(Symbols.search),
                  suffixIcon: SearchFieldActions(
                    controller: _search,
                    onClear: () => setState(() {}),
                  ),
                ),
              ),
            ),
            Expanded(
              child: names.isEmpty && _actions.kept(_kind).isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          query.isNotEmpty
                              ? 'No matches for “${_search.text.trim()}”'
                              : _kind == LibraryKind.tags
                              ? 'No tags yet'
                              : 'No ingredients yet',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : CustomScrollView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      slivers: [
                        if (_actions.checkingDuplicates(_kind))
                          const SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Text('Checking possible duplicates…'),
                            ),
                          ),
                        if (duplicates.isNotEmpty)
                          _duplicatesCard(context, duplicates, wide),
                        if (_actions.kept(_kind).isNotEmpty)
                          SliverToBoxAdapter(
                            child: ListTile(
                              title: Text(
                                'Kept separate (${_actions.kept(_kind).length})',
                              ),
                              trailing: const Icon(Symbols.chevron_right),
                              onTap: _showAllDuplicates,
                            ),
                          ),
                        for (final group in letters.entries)
                          SliverMainAxisGroup(
                            slivers: [
                              SliverPersistentHeader(
                                pinned: true,
                                delegate: _LetterHeader(
                                  group.key,
                                  Theme.of(context),
                                  MediaQuery.textScalerOf(context),
                                ),
                              ),
                              SliverList.builder(
                                itemCount: group.value.length,
                                itemBuilder: (_, i) =>
                                    _nameRow(context, group.value[i], wide),
                              ),
                            ],
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      ],
                    ),
            ),
          ],
        );
        final selected = _selected == null ? null : catalog.named(_selected!);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Library'),
            actions: [
              if (_kind == LibraryKind.tags)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: FilledButton.tonalIcon(
                    onPressed: _actions.busy
                        ? null
                        : () async {
                            final tag = await addTagToRecipes(
                              context,
                              widget.store,
                            );
                            if (mounted && tag != null) {
                              setState(() => _selected = tag);
                            }
                          },
                    icon: const Icon(Symbols.add),
                    label: const Text('New tag'),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: wide
                ? Row(
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth * .38).clamp(280, 400),
                        child: list,
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: selected == null
                            ? Center(
                                child: Text(
                                  'Choose a name to see its recipes',
                                  style: Theme.of(context).textTheme.bodyLarge,
                                ),
                              )
                            : _NameDetails(
                                key: ValueKey((_kind, selected.name)),
                                actions: _actions,
                                kind: _kind,
                                name: selected,
                                onOpenRecipe: widget.onOpenRecipe,
                                onChanged: (name) =>
                                    setState(() => _selected = name),
                              ),
                      ),
                    ],
                  )
                : list,
          ),
        );
      },
    ),
  );
  Widget _duplicatesCard(
    BuildContext context,
    List<List<LibraryName>> groups,
    bool wide,
  ) {
    final theme = Theme.of(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Card(
          key: const Key('library-duplicates-card'),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .5,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Possible duplicates',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: PixelSingleChildScrollView(
                      child: Column(
                        children: [
                          for (final group in groups.take(1)) ...[
                            _duplicateGroup(context, group, wide),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _showAllDuplicates,
                      child: Text('Show all (${groups.length})'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _duplicateGroup(
    BuildContext context,
    List<LibraryName> group,
    bool wide,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (hasSimilarSpelling(group))
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
            'Similar spelling',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      for (final name in group) _nameRow(context, name, wide, compact: true),
      Align(
        alignment: Alignment.centerRight,
        child: Wrap(
          spacing: 8,
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              onPressed: _actions.busy
                  ? null
                  : () => _keepSeparate(context, group),
              child: const Text('Keep separate'),
            ),
            FilledButton.tonal(
              onPressed: _actions.busy
                  ? null
                  : () => _actions.confirmChange(
                      context,
                      _kind,
                      group.skip(1).toList(),
                      group.first,
                      'Merge',
                      choices: group,
                    ),
              child: const Text('Merge'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
    ],
  );

  void _keepSeparate(BuildContext context, List<LibraryName> group) {
    final kind = _kind.name;
    final names = group.map((n) => n.name).toList();
    final prefs = widget.store.preferences;
    prefs.keepSeparate(kind, names);
    showFeedbackWithMessenger(
      ScaffoldMessenger.of(context),
      'Kept separate',
      duration: const Duration(seconds: 10),
      onUndo: () async {
        prefs.showTogether(kind, names);
      },
    );
  }

  void _showAllDuplicates() {
    Navigator.of(context).push(
      cookdexRoute<void>(
        context,
        builder: (context) => AnimatedBuilder(
          animation: _actions,
          builder: (context, _) {
            final groups = _actions.duplicates(_kind);
            final kept = _actions.kept(_kind);
            return Scaffold(
              appBar: AppBar(title: const Text('Possible duplicates')),
              body: PixelListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: groups.length + kept.length + 1,
                itemBuilder: (context, i) {
                  if (i < groups.length) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: _duplicateGroup(context, groups[i], false),
                        ),
                      ),
                    );
                  }
                  if (i == groups.length) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (groups.isEmpty) ...[
                            Text(
                              _actions.checkingDuplicates(_kind)
                                  ? 'Checking possible duplicates…'
                                  : 'No possible duplicates',
                            ),
                            const SizedBox(height: 24),
                          ],
                          Text(
                            'Kept separate (${kept.length})',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    );
                  }
                  final names = kept[i - groups.length - 1];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final name in names)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: _kind == LibraryKind.tags
                                    ? Align(
                                        alignment: Alignment.centerLeft,
                                        child: TonalTag(name),
                                      )
                                    : Text(name),
                              ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => widget.store.preferences
                                    .showTogether(_kind.name, names),
                                child: const Text('Show again'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _nameRow(
    BuildContext context,
    LibraryName name,
    bool wide, {
    bool compact = false,
  }) => GestureDetector(
    onSecondaryTapDown: _actions.busy
        ? null
        : (details) async {
            final overlay =
                Overlay.of(context).context.findRenderObject()! as RenderBox;
            final point = overlay.globalToLocal(details.globalPosition);
            final action = await showMenu<String>(
              context: context,
              position: RelativeRect.fromRect(
                Rect.fromLTWH(point.dx, point.dy, 0, 0),
                Offset.zero & overlay.size,
              ),
              items: [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(value: 'merge', child: Text('Merge into…')),
                if (_kind == LibraryKind.tags)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(
                      'Remove tag',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            );
            if (!context.mounted) return;
            if (action == 'rename') await _actions.rename(context, _kind, name);
            if (!context.mounted) return;
            if (action == 'merge') {
              await _actions.pickMerge(context, _kind, name);
            }
            if (!context.mounted) return;
            if (action == 'remove') {
              await _actions.confirmChange(
                context,
                _kind,
                [name],
                null,
                'Remove tag',
              );
            }
          },
    child: Material(
      color: wide && _selected == name.name
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      borderRadius: compact ? BorderRadius.circular(8) : null,
      child: ListTile(
        key: ValueKey(('library-name', compact, name.name)),
        contentPadding: EdgeInsets.symmetric(horizontal: compact ? 8 : 16),
        selected: wide && _selected == name.name,
        selectedColor: Theme.of(context).colorScheme.onPrimaryContainer,
        title: _kind == LibraryKind.tags
            ? Align(alignment: Alignment.centerLeft, child: TonalTag(name.name))
            : Text(name.name),
        trailing: Text(
          '${name.count}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        minVerticalPadding: compact ? 4 : 12,
        minTileHeight: compact ? 48 : null,
        onTap: () => _select(name, wide),
      ),
    ),
  );
}

class _LetterHeader extends SliverPersistentHeaderDelegate {
  _LetterHeader(this.letter, this.theme, this.scaler);
  final String letter;
  final ThemeData theme;
  final TextScaler scaler;
  @override
  double get minExtent => maxExtent;
  @override
  double get maxExtent => scaler.scale(20) + 20;
  @override
  bool shouldRebuild(_LetterHeader old) =>
      old.letter != letter || old.theme != theme || old.scaler != scaler;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: theme.colorScheme.surfaceContainerLow,
    child: Semantics(
      header: true,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          letter,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    ),
  );
}

class _NamePage extends StatefulWidget {
  const _NamePage({
    required this.actions,
    required this.kind,
    required this.name,
    required this.onOpenRecipe,
  });
  final _LibraryActions actions;
  final LibraryKind kind;
  final String name;
  final LibraryRecipeOpener onOpenRecipe;
  @override
  State<_NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<_NamePage> {
  late String _name = widget.name;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.actions,
    builder: (context, _) {
      final name = widget.actions.catalog(widget.kind).named(_name);
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.kind == LibraryKind.tags ? 'Tag' : 'Ingredient'),
        ),
        body: SafeArea(
          top: false,
          child: name == null
              ? const Center(child: Text('This name is no longer used.'))
              : _NameDetails(
                  actions: widget.actions,
                  kind: widget.kind,
                  name: name,
                  onOpenRecipe: widget.onOpenRecipe,
                  onChanged: (value) {
                    if (value == null) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _name = value);
                    }
                  },
                ),
        ),
      );
    },
  );
}

class _NameDetails extends StatelessWidget {
  const _NameDetails({
    super.key,
    required this.actions,
    required this.kind,
    required this.name,
    required this.onOpenRecipe,
    required this.onChanged,
  });
  final _LibraryActions actions;
  final LibraryKind kind;
  final LibraryName name;
  final LibraryRecipeOpener onOpenRecipe;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => PixelListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(name.name, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(
        recipeCount(name.count),
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 24),
      Card(
        child: Column(
          children: [
            for (final (index, recipe) in name.recipes.take(3).indexed) ...[
              if (index > 0) const Divider(),
              _UsageRow(
                store: actions.store,
                recipe: recipe,
                kind: kind,
                names: [name.name],
                onTap: () => onOpenRecipe(context, recipe.id),
              ),
            ],
            if (name.count > 3) ...[
              const Divider(),
              ListTile(
                title: Text('Show all (${name.count})'),
                trailing: const Icon(Symbols.chevron_right),
                onTap: () => Navigator.of(context).push(
                  cookdexRoute<void>(
                    context,
                    builder: (_) => _AllRecipes(
                      actions: actions,
                      kind: kind,
                      name: name.name,
                      onOpenRecipe: onOpenRecipe,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.tonalIcon(
            onPressed: actions.busy
                ? null
                : () =>
                      actions.rename(context, kind, name, onChanged: onChanged),
            icon: const Icon(Symbols.edit),
            label: const Text('Rename'),
          ),
          OutlinedButton.icon(
            onPressed: actions.busy
                ? null
                : () => actions.pickMerge(
                    context,
                    kind,
                    name,
                    onChanged: onChanged,
                  ),
            icon: const Icon(Symbols.merge),
            label: const Text('Merge into…'),
          ),
          if (kind == LibraryKind.tags)
            OutlinedButton.icon(
              onPressed: actions.busy
                  ? null
                  : () =>
                        addTagToRecipes(context, actions.store, tag: name.name),
              icon: const Icon(Symbols.playlist_add),
              label: const Text('Add to recipes…'),
            ),
        ],
      ),
      if (kind == LibraryKind.tags)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: actions.busy
                  ? null
                  : () => actions.confirmChange(
                      context,
                      kind,
                      [name],
                      null,
                      'Remove tag',
                      onChanged: onChanged,
                    ),
              icon: const Icon(Symbols.delete),
              label: const Text('Remove tag'),
            ),
          ),
        ),
    ],
  );
}

class _AllRecipes extends StatelessWidget {
  const _AllRecipes({
    required this.actions,
    required this.kind,
    required this.name,
    required this.onOpenRecipe,
  });
  final _LibraryActions actions;
  final LibraryKind kind;
  final String name;
  final LibraryRecipeOpener onOpenRecipe;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: actions,
    builder: (context, _) {
      final recipes =
          actions.catalog(kind).named(name)?.recipes ?? <core.RecipeSummary>[];
      return Scaffold(
        appBar: AppBar(title: Text(name)),
        body: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(recipeCount(recipes.length)),
              ),
              Expanded(
                child: PixelListView.builder(
                  itemCount: recipes.length,
                  itemBuilder: (_, i) => _UsageRow(
                    key: ValueKey((recipes[i].id, recipes[i].revision)),
                    store: actions.store,
                    recipe: recipes[i],
                    kind: kind,
                    names: [name],
                    onTap: () => onOpenRecipe(context, recipes[i].id),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<List<String>> _ingredientLines(
  RecipeStore store,
  core.RecipeSummary summary,
  List<String> names,
) async {
  final recipe = await store.detail(summary.id);
  if (recipe == null || recipe.revision != summary.revision) {
    throw StateError('Recipe changed');
  }
  final amounts = await store.ingredientAmounts(recipe.id);
  if (store.cachedDetail(recipe.id)?.revision != summary.revision) {
    throw StateError('Recipe changed');
  }
  return [
    for (final (i, ingredient) in recipe.fields.ingredients.indexed)
      if (names.contains(ingredient.name))
        '${[amounts[i], ingredient.unit, ingredient.name].where((s) => s.isNotEmpty).join(' ')}${ingredient.prepNote.isEmpty ? '' : ', ${ingredient.prepNote}'}${ingredient.optional ? ' (optional)' : ''}',
  ];
}

class _UsageRow extends StatefulWidget {
  const _UsageRow({
    super.key,
    required this.store,
    required this.recipe,
    required this.kind,
    required this.names,
    this.onTap,
  });
  final RecipeStore store;
  final core.RecipeSummary recipe;
  final LibraryKind kind;
  final List<String> names;
  final VoidCallback? onTap;
  @override
  State<_UsageRow> createState() => _UsageRowState();
}

class _UsageRowState extends State<_UsageRow> {
  late Future<List<String>> _lines = _load();
  Future<List<String>> _load() => widget.kind == LibraryKind.tags
      ? Future.value([])
      : _ingredientLines(widget.store, widget.recipe, widget.names);
  @override
  void didUpdateWidget(_UsageRow old) {
    super.didUpdateWidget(old);
    if (old.recipe.revision != widget.recipe.revision ||
        old.recipe.id != widget.recipe.id ||
        old.kind != widget.kind ||
        old.names.join('\u0000') != widget.names.join('\u0000')) {
      _lines = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _lines,
    builder: (context, snapshot) => ListTile(
      title: Text(widget.recipe.title),
      subtitle: widget.kind == LibraryKind.tags
          ? null
          : Text(
              snapshot.hasError
                  ? 'Could not load ingredient lines'
                  : snapshot.data?.join('\n') ?? 'Loading ingredients…',
            ),
      trailing: widget.onTap == null ? null : const Icon(Symbols.chevron_right),
      minVerticalPadding: 12,
      onTap: widget.onTap,
    ),
  );
}

class _LibraryActions extends ChangeNotifier {
  _LibraryActions(this.store) {
    store.addListener(_changed);
    store.preferences.addListener(_changed);
  }
  final RecipeStore store;
  bool busy = false;
  bool _disposed = false;
  List<core.RecipeSummary>? _summaries;
  final _catalogs = <LibraryKind, LibraryCatalog>{};
  final _duplicates = <LibraryKind, List<List<LibraryName>>>{};
  final _pendingDuplicates = <LibraryKind>{};
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  bool checkingDuplicates(LibraryKind kind) =>
      _pendingDuplicates.contains(kind);
  List<List<String>> kept(LibraryKind kind) =>
      store.preferences.keptSeparate(kind.name);
  List<List<LibraryName>> duplicates(LibraryKind kind) {
    final current = catalog(kind);
    if (current.names.length <= 160) {
      _duplicates[kind] ??= current.duplicates;
    } else if (!_duplicates.containsKey(kind) && _pendingDuplicates.add(kind)) {
      current.loadDuplicates().then((groups) {
        if (_disposed || !identical(_catalogs[kind], current)) return;
        _duplicates[kind] = groups;
        _pendingDuplicates.remove(kind);
        notifyListeners();
      });
    }
    return (_duplicates[kind] ?? const <List<LibraryName>>[])
        .where(
          (g) => !store.preferences.isKeptSeparate(
            kind.name,
            g.map((n) => n.name),
          ),
        )
        .toList();
  }

  LibraryCatalog catalog(LibraryKind kind) {
    if (!identical(_summaries, store.summaries)) {
      _summaries = store.summaries;
      _catalogs.clear();
      _duplicates.clear();
      _pendingDuplicates.clear();
    }
    return _catalogs.putIfAbsent(kind, () => LibraryCatalog(_summaries!, kind));
  }

  @override
  void dispose() {
    _disposed = true;
    store.removeListener(_changed);
    store.preferences.removeListener(_changed);
    super.dispose();
  }

  Future<void> rename(
    BuildContext context,
    LibraryKind kind,
    LibraryName name, {
    ValueChanged<String?>? onChanged,
  }) async {
    final generation = store.generation;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(name: name, catalog: catalog(kind)),
    );
    if (result == null || !context.mounted) return;
    final existing = catalog(kind).matching(result, name.name);
    if (existing != null) {
      await confirmChange(
        context,
        kind,
        [name],
        existing,
        'Merge',
        generation: generation,
        onChanged: onChanged,
      );
    } else {
      await _apply(
        context,
        kind,
        [name],
        result,
        'Renamed',
        generation,
        onChanged,
      );
    }
  }

  Future<void> pickMerge(
    BuildContext context,
    LibraryKind kind,
    LibraryName name, {
    ValueChanged<String?>? onChanged,
  }) async {
    final generation = store.generation;
    final target = await Navigator.of(context).push<LibraryName>(
      cookdexRoute<LibraryName>(
        context,
        builder: (_) =>
            _MergePicker(name: name, kind: kind, names: catalog(kind).names),
      ),
    );
    if (target == null || !context.mounted) return;
    await confirmChange(
      context,
      kind,
      [name],
      target,
      'Merge',
      generation: generation,
      onChanged: onChanged,
    );
  }

  Future<void> confirmChange(
    BuildContext context,
    LibraryKind kind,
    List<LibraryName> sources,
    LibraryName? target,
    String action, {
    int? generation,
    List<LibraryName>? choices,
    ValueChanged<String?>? onChanged,
  }) async {
    final expected = generation ?? store.generation;
    if (target == null) {
      final count = _changingRecipes(sources).length;
      final confirmed = await confirmCookdex(
        context,
        title: 'Remove tag?',
        action: action,
        destructive: true,
        content: Text(
          'Remove “${sources.single.name}” from ${recipeCount(count)}?\n\nYour recipes won\'t be deleted.',
        ),
      );
      if (!confirmed || !context.mounted) return;
    } else {
      final selected = await showDialog<LibraryName>(
        context: context,
        builder: (_) => _MergeConfirmation(
          store: store,
          kind: kind,
          sources: sources,
          target: target!,
          choices: choices,
        ),
      );
      if (selected == null || !context.mounted) return;
      target = selected;
      if (choices != null) {
        sources = choices.where((n) => n.name != selected.name).toList();
      }
    }
    await _apply(
      context,
      kind,
      sources,
      target?.name,
      target == null ? 'Removed tag' : 'Merged',
      expected,
      onChanged,
    );
  }

  Future<void> _apply(
    BuildContext context,
    LibraryKind kind,
    List<LibraryName> sources,
    String? target,
    String verb,
    int generation,
    ValueChanged<String?>? onChanged,
  ) async {
    if (busy) return;
    busy = true;
    _changed();
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Updating Library'),
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
      final result = await store.changeLibraryNames(
        generation,
        kind == LibraryKind.tags,
        sources.map((n) => n.name).toList(),
        target,
      );
      if (progress.isActive) navigator.removeRoute(progress);
      if (context.mounted) onChanged?.call(target);
      showFeedbackWithMessenger(
        messenger,
        '$verb ${verb == 'Removed tag' ? 'from' : 'in'} ${recipeCount(result.count)}',
        duration: const Duration(seconds: 10),
        onUndo: () async {
          if (busy) return;
          busy = true;
          _changed();
          try {
            await store.undoLibraryNames(result.undo);
            if (context.mounted && sources.length == 1) {
              onChanged?.call(sources.single.name);
            }
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
          } finally {
            busy = false;
            _changed();
          }
        },
      );
    } catch (_) {
      showFeedbackWithMessenger(
        messenger,
        'Could not update Library. Nothing changed. Review the names and try again.',
        kind: FeedbackKind.error,
      );
    } finally {
      if (progress.isActive) navigator.removeRoute(progress);
      busy = false;
      _changed();
    }
  }
}

List<core.RecipeSummary> _changingRecipes(List<LibraryName> sources) => {
  for (final source in sources)
    for (final recipe in source.recipes) recipe.id: recipe,
}.values.toList()..sort((a, b) => compareNames(a.title, b.title));

class _MergeConfirmation extends StatefulWidget {
  const _MergeConfirmation({
    required this.store,
    required this.kind,
    required this.sources,
    required this.target,
    this.choices,
  });
  final RecipeStore store;
  final LibraryKind kind;
  final List<LibraryName> sources;
  final LibraryName target;
  final List<LibraryName>? choices;
  @override
  State<_MergeConfirmation> createState() => _MergeConfirmationState();
}

class _MergeConfirmationState extends State<_MergeConfirmation> {
  late LibraryName _target = widget.target;
  List<LibraryName> get _sources =>
      widget.choices?.where((n) => n.name != _target.name).toList() ??
      widget.sources;
  late Future<List<List<String>>> _lines = _load();
  Future<List<List<String>>> _load() async {
    if (widget.kind == LibraryKind.tags) return [];
    final names = _sources.map((n) => n.name).toList();
    return Future.wait(
      _changingRecipes(_sources)
          .take(5)
          .map((recipe) => _ingredientLines(widget.store, recipe, names)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recipes = _changingRecipes(_sources);
    final sourceText = _sources
        .map((n) => '“${n.name}” (${recipeCount(n.count)})')
        .join(', ');
    final warning = widget.kind == LibraryKind.ingredients
        ? libraryNumberWarning(
            _sources.map((n) => n.name).toList(),
            _target.name,
          )
        : null;
    return FutureBuilder<List<List<String>>>(
      future: _lines,
      builder: (context, snapshot) => AlertDialog(
        title: const Text('Merge names?'),
        content: SizedBox(
          width: 420,
          child: PixelSingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.choices != null) ...[
                  Text(
                    'Spelling to keep',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<LibraryName>(
                    groupValue: _target,
                    onChanged: (value) {
                      if (value == null || value == _target) return;
                      setState(() {
                        _target = value;
                        _lines = _load();
                      });
                    },
                    child: Column(
                      children: [
                        for (final name in widget.choices!)
                          RadioListTile<LibraryName>(
                            value: name,
                            title: Text(name.name),
                            subtitle: Text(recipeCount(name.count)),
                            contentPadding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Merge $sourceText into “${_target.name}” (${recipeCount(_target.count)})?',
                ),
                if (warning != null) ...[
                  const SizedBox(height: 16),
                  Text(warning),
                ],
                const SizedBox(height: 20),
                Text(
                  'Recipes that will change',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'The Library changed. Cancel and review the names again.',
                    ),
                  )
                else if (snapshot.connectionState != ConnectionState.done)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Loading ingredient lines…'),
                  )
                else ...[
                  for (final (i, recipe) in recipes.take(5).indexed)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            recipe.title,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          if (widget.kind == LibraryKind.ingredients)
                            Text(
                              snapshot.data![i].join('\n'),
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                        ],
                      ),
                    ),
                  if (recipes.length > 5)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('and ${recipes.length - 5} more'),
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
            onPressed:
                snapshot.connectionState == ConnectionState.done &&
                    !snapshot.hasError
                ? () => Navigator.pop(context, _target)
                : null,
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name, required this.catalog});
  final LibraryName name;
  final LibraryCatalog catalog;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.name.name);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = normalizeNameWhitespace(_text.text);
    final match = value == widget.name.name
        ? null
        : widget.catalog.matching(value, widget.name.name);
    return AlertDialog(
      title: const Text('Rename'),
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
                  autofocus: true,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                match == null
                    ? 'Rename in ${recipeCount(widget.name.count)}.'
                    : 'This matches “${match.name}” (${recipeCount(match.count)}), so they\'ll be merged.',
              ),
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
          onPressed: value.isEmpty || value == widget.name.name
              ? null
              : () => Navigator.pop(context, value),
          child: Text(match == null ? 'Rename' : 'Continue'),
        ),
      ],
    );
  }
}

class _MergePicker extends StatefulWidget {
  const _MergePicker({
    required this.name,
    required this.names,
    required this.kind,
  });
  final LibraryName name;
  final List<LibraryName> names;
  final LibraryKind kind;
  @override
  State<_MergePicker> createState() => _MergePickerState();
}

class _MergePickerState extends State<_MergePicker> {
  final _query = TextEditingController();
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.names
        .where(
          (n) =>
              n.name != widget.name.name &&
              n.name.toLowerCase().contains(_query.text.trim().toLowerCase()),
        )
        .toList();
    final similar = available
        .where((n) => similarLibraryName(widget.name.name, n.name))
        .toList();
    final rest = available.where((n) => !similar.contains(n)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Merge into…')),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text('Choose a name for “${widget.name.name}”.'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search names',
                  prefixIcon: const Icon(Symbols.search),
                  suffixIcon: SearchFieldActions(
                    controller: _query,
                    onClear: () => setState(() {}),
                  ),
                ),
              ),
            ),
            Expanded(
              child: available.isEmpty
                  ? const Center(child: Text('No matching names'))
                  : CustomScrollView(
                      slivers: [
                        for (final (title, names) in [
                          ('Similar names', similar),
                          ('All names', rest),
                        ])
                          if (names.isNotEmpty) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  title,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                            SliverList.builder(
                              itemCount: names.length,
                              itemBuilder: (_, i) => ListTile(
                                title: widget.kind == LibraryKind.tags
                                    ? Align(
                                        alignment: Alignment.centerLeft,
                                        child: TonalTag(names[i].name),
                                      )
                                    : Text(names[i].name),
                                trailing: Text(
                                  '${names[i].count}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                minVerticalPadding: 12,
                                onTap: () => Navigator.pop(context, names[i]),
                              ),
                            ),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
