import 'pixel_scroll.dart';
import 'retained_screen.dart';
import '../sync_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../local_preferences.dart';
import '../recipe_store.dart';
import '../tag_labels.dart';
import '../src/rust/api.dart';
import 'components.dart';
import 'feedback.dart';
import 'navigation_feedback.dart';
import 'recipe_grid.dart';
import 'recipe_metadata.dart';
import '../sync_presentation.dart';
import 'sync_indicator.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({
    super.key,
    required this.store,
    required this.preferences,
    required this.onOpenRecipe,
    required this.onAdd,
    required this.onActions,
    this.controller,
    this.onWrite,
    this.onImport,
    this.onSync,
    this.syncStatus,
    this.syncController,
    this.onSyncStatus,
    this.onHelp,
    this.onRestore,
    this.selectedIds,
    this.onToggleSelection,
    this.onCloseSelection,
    this.onSelectAll,
    this.onShareSelection,
    this.onShoppingSelection,
  });

  /// Null means normal browsing; an empty set keeps selection mode active.
  final Set<String>? selectedIds;
  final ValueChanged<String>? onToggleSelection;
  final VoidCallback? onCloseSelection,
      onSelectAll,
      onShareSelection,
      onShoppingSelection;
  final SyncPresentation? syncStatus;
  final SyncController? syncController;
  final VoidCallback? onSyncStatus, onHelp, onRestore;
  final RecipeStore store;
  final LocalPreferences preferences;
  final ValueChanged<String> onOpenRecipe;
  final VoidCallback onAdd;
  final ValueChanged<RecipeSummary> onActions;
  final ScrollController? controller;
  final VoidCallback? onWrite;
  final VoidCallback? onImport;
  final Future<void> Function()? onSync;

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  late final TextEditingController _query;
  late final ScrollController _scroll;
  final _showAdd = ValueNotifier(true);
  final Map<String, _RecipeRow> _rows = {};

  Widget _row(RecipeSummary recipe, {required bool grid}) {
    final existing = _rows[recipe.id];
    if (existing != null &&
        identical(existing.recipe, recipe) &&
        existing.view == widget.preferences.view &&
        existing.grid == grid &&
        existing.selecting == (widget.selectedIds != null) &&
        existing.selected ==
            (widget.selectedIds?.contains(recipe.id) ?? false)) {
      return existing;
    }
    return _rows[recipe.id] = _RecipeRow(
      key: ValueKey(recipe.id),
      recipe: recipe,
      view: widget.preferences.view,
      grid: grid,
      selecting: widget.selectedIds != null,
      selected: widget.selectedIds?.contains(recipe.id) ?? false,
      onOpen: (id) => widget.selectedIds != null
          ? widget.onToggleSelection?.call(id)
          : widget.onOpenRecipe(id),
      onActions: (value) => widget.onActions(value),
      onFavorite: () => _favorite(recipe),
    );
  }

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.preferences.query);
    _scroll =
        widget.controller ??
        PixelScrollController(
          initialScrollOffset: widget.preferences.scrollOffset,
        );
    _scroll.addListener(_saveScroll);
    widget.preferences.addListener(_syncQuery);
  }

  void _saveScroll() => widget.preferences.setScrollOffset(_scroll.offset);
  void _syncQuery() {
    if (_query.text != widget.preferences.query) {
      _query.value = TextEditingValue(
        text: widget.preferences.query,
        selection: TextSelection.collapsed(
          offset: widget.preferences.query.length,
        ),
      );
    }
    if (widget.preferences.scrollOffset == 0 &&
        _scroll.hasClients &&
        _scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_syncQuery);
    _scroll.removeListener(_saveScroll);
    if (widget.controller == null) _scroll.dispose();
    _query.dispose();
    _showAdd.dispose();
    super.dispose();
  }

  Future<void> _fields() => showCookdexSheet<void>(
    context,
    child: StatefulBuilder(
      builder: (context, update) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Search in',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (final field in SearchField.values)
            CheckboxListTile(
              title: Text(_fieldLabel(field)),
              value: widget.preferences.searchFields.contains(field),
              onChanged: (checked) {
                final fields = {...widget.preferences.searchFields};
                checked! ? fields.add(field) : fields.remove(field);
                widget.preferences.setSearchFields(fields);
                update(() {});
              },
            ),
          TextButton(
            onPressed: () {
              widget.preferences.resetSearch();
              update(() {});
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    ),
  );

  Widget _choiceMenu<T>({
    required String tooltip,
    required String label,
    required List<T> values,
    required T selected,
    required String Function(T) labelFor,
    required void Function(T) onSelected,
    double? labelWidth,
  }) => MenuAnchor(
    style: const MenuStyle(alignment: AlignmentDirectional.bottomStart),
    menuChildren: [
      for (final value in values)
        MenuItemButton(
          trailingIcon: selected == value ? const Icon(Symbols.check) : null,
          onPressed: () => onSelected(value),
          child: Text(labelFor(value)),
        ),
    ],
    builder: (context, controller, child) => ActionChip(
      tooltip: tooltip,
      onPressed: () =>
          controller.isOpen ? controller.close() : controller.open(),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reserve the widest option so selecting another sort never moves
          // the neighboring controls or changes the horizontal scroll extent.
          SizedBox(width: labelWidth, child: Text(label)),
          const SizedBox(width: 4),
          const Icon(Symbols.arrow_drop_down, size: 18),
        ],
      ),
    ),
  );

  Widget _selectionBar() => Row(
    children: [
      IconButton(
        tooltip: 'Close selection',
        onPressed: widget.onCloseSelection,
        icon: const Icon(Symbols.close),
      ),
      Expanded(
        child: Text(
          '${widget.selectedIds!.length} selected',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ),
      IconButton(
        tooltip: 'Select all',
        onPressed: widget.onSelectAll,
        icon: const Icon(Symbols.select_all),
      ),
      IconButton(
        tooltip: 'Share selected recipes',
        onPressed: widget.selectedIds!.isEmpty ? null : widget.onShareSelection,
        icon: const Icon(Symbols.share),
      ),
      IconButton(
        tooltip: 'Add selected recipes to shopping list',
        onPressed: widget.selectedIds!.isEmpty
            ? null
            : widget.onShoppingSelection,
        icon: const Icon(Symbols.shopping_cart),
      ),
    ],
  );

  Widget _controls() {
    final theme = Theme.of(context);
    var sortWidth = 0.0;
    for (final sort in RecipeSort.values) {
      final painter = TextPainter(
        text: TextSpan(
          text: _sortLabel(sort),
          style: theme.chipTheme.labelStyle ?? theme.textTheme.labelLarge,
        ),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      if (painter.width > sortWidth) sortWidth = painter.width;
      painter.dispose();
    }
    final controls = <Widget>[
      FilterChip(
        label: const Text('Favorites'),
        avatar: Icon(
          Symbols.star,
          fill: widget.preferences.favoritesOnly ? 1 : 0,
          size: 18,
        ),
        selectedColor: theme.colorScheme.secondaryContainer,
        selected: widget.preferences.favoritesOnly,
        showCheckmark: false,
        onSelected: widget.preferences.setFavoritesOnly,
      ),
      _choiceMenu<RecipeSort>(
        labelWidth: sortWidth.ceilToDouble(),
        tooltip: 'Sort recipes',
        label: _sortLabel(widget.preferences.sort),
        values: RecipeSort.values,
        selected: widget.preferences.sort,
        labelFor: _sortLabel,
        onSelected: widget.preferences.setSort,
      ),
      IconButton(
        key: const Key('recipe-view'),
        tooltip: widget.preferences.view == RecipeView.cards
            ? 'Switch to Compact view'
            : 'Switch to Cards view',
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        onPressed: () => widget.preferences.setView(
          widget.preferences.view == RecipeView.cards
              ? RecipeView.compact
              : RecipeView.cards,
        ),
        icon: Icon(
          widget.preferences.view == RecipeView.cards
              ? Symbols.view_list
              : Symbols.view_agenda,
        ),
      ),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, control) in controls.indexed) ...[
          if (index > 0) const SizedBox(width: 8),
          control,
        ],
      ],
    );
  }

  Widget _search() => PixelScrollScope(
    axis: Axis.horizontal,
    builder: (context) => TextField(
      scrollController: PrimaryScrollController.of(context),
      key: const Key('recipe-search'),
      controller: _query,
      onChanged: widget.preferences.setQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search recipes',
        prefixIcon: const Icon(Symbols.search),
        suffixIcon: IconButton(
          tooltip: 'Search fields',
          onPressed: _fields,
          icon: const Icon(Symbols.tune),
        ),
      ),
    ),
  );

  Widget _wideToolbar() => RecipeSearchToolbar(
    key: const Key('wide-recipe-toolbar'),
    search: _search(),
    controls: _controls(),
  );

  Widget _emptyLibrary(BuildContext context, double width) {
    final theme = Theme.of(context);
    final label = TextPainter(
      text: TextSpan(text: 'Write a recipe', style: theme.textTheme.labelLarge),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final stack = (width - 48).clamp(0, 520) < (label.width + 48) * 2 + 12;
    label.dispose();
    final import = FilledButton(
      key: const Key('empty-smart-import'),
      onPressed: widget.onImport ?? widget.onAdd,
      child: const Text('Smart Import'),
    );
    final write = OutlinedButton(
      key: const Key('empty-write-recipe'),
      onPressed: widget.onWrite ?? widget.onAdd,
      child: const Text('Write a recipe'),
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.store.setAsideCount > 0
                    ? 'No readable recipes'
                    : 'No recipes caught yet',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Import one from a photo, link or text, or write your own.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (stack)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [import, const SizedBox(height: 12), write],
                )
              else
                Row(
                  children: [
                    Expanded(child: import),
                    const SizedBox(width: 12),
                    Expanded(child: write),
                  ],
                ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  if (widget.onRestore != null)
                    TextButton(
                      onPressed: widget.onRestore,
                      child: const Text('Restore a backup'),
                    ),
                  if (widget.onHelp != null)
                    TextButton(
                      onPressed: widget.onHelp,
                      child: const Text('How cookdex works'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _discarding = false;

  Future<void> _manageSetAside() async {
    final count = widget.store.setAsideCount;
    final generation = widget.store.generation;
    final discard = await confirmCookdex(
      context,
      title: '$count ${count == 1 ? 'recipe' : 'recipes'} set aside',
      action: 'Discard…',
      destructive: true,
      content: const PixelSingleChildScrollView(
        child: Text(
          'These recipes could not be read safely. Your other recipes are still available. Sync is paused until the set-aside recipes are restored or discarded.\n\n'
          'To keep them, use Settings > Backup & restore to restore a known-good recipe ZIP or recover the previous save. A new ZIP includes only readable recipes.\n\n'
          'Discard only if you no longer need these recipes.',
        ),
      ),
    );
    if (!discard || !mounted) return;
    final confirmed = await confirmCookdex(
      context,
      title: 'Discard set-aside recipes?',
      action: 'Discard',
      destructive: true,
      content: const PixelSingleChildScrollView(
        child: Text(
          'This permanently deletes the set-aside recipes. You cannot undo this. '
          'Their deletion will sync to your paired devices when sync resumes. '
          'Your readable recipes will stay.',
        ),
      ),
    );
    if (!confirmed || !mounted) return;
    setState(() => _discarding = true);
    try {
      await widget.store.discardSetAside(generation);
      if (mounted) showFeedback(context, 'Set-aside recipes discarded');
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Could not discard recipes. Refresh and try again.',
          kind: FeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _discarding = false);
    }
  }

  Widget _setAsideNotice() {
    final count = widget.store.setAsideCount;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count ${count == 1 ? 'recipe' : 'recipes'} set aside · Sync paused',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              widget.store.summaries.isEmpty
                  ? 'Restore or discard these recipes to resume sync.'
                  : 'Your readable recipes are still available.',
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _discarding ? null : _manageSetAside,
                child: const Text('Review options'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: Listenable.merge([widget.store, widget.preferences]),
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final recipes = widget.store.visibleRecipes;
        final currentIds = widget.store.summaries
            .map((recipe) => recipe.id)
            .toSet();
        _rows.removeWhere((id, _) => !currentIds.contains(id));
        final columns = recipeGridColumns(constraints.maxWidth - 32);
        final grid = columns > 1 && widget.preferences.view == RecipeView.cards;
        final cardHeight = grid ? recipeGridCardHeight(context) : null;
        final rowIndices = <String, int>{
          for (var i = 0; i < recipes.length; i += columns)
            'group-${recipes[i].id}': i ~/ columns,
        };
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final searchHeight = 72.0 + (scale - 1).clamp(0, 3) * 24;
        final wide = MediaQuery.sizeOf(context).width >= 600;
        return Stack(
          children: [
            NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                if (notification.direction != ScrollDirection.idle) {
                  final show =
                      notification.direction == ScrollDirection.forward;
                  _showAdd.value = show;
                }
                return false;
              },
              child: RefreshIndicator(
                onRefresh: widget.onSync ?? () async {},
                child: PixelCustomScrollView(
                  key: const PageStorageKey('recipes-scroll'),
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPersistentHeader(
                      pinned:
                          widget.selectedIds != null ||
                          widget.syncStatus != null ||
                          widget.syncController != null,
                      delegate: _PinnedSearch(
                        height: 56 + (scale - 1).clamp(0, 3) * 24,
                        child: ColoredBox(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: widget.selectedIds != null
                                ? _selectionBar()
                                : Row(
                                    children: [
                                      if (wide || scale < 1.6) ...[
                                        const Icon(Symbols.skillet, size: 28),
                                        const SizedBox(width: 10),
                                      ],
                                      Expanded(
                                        child: Text(
                                          'cookdex',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                      if (widget.syncStatus != null ||
                                          widget.syncController != null)
                                        VisibleListenableBuilder(
                                          listenable: widget.syncController,
                                          builder: (_) => SyncIndicator(
                                            status:
                                                widget.syncController == null
                                                ? widget.syncStatus!
                                                : syncPresentation(
                                                    widget.syncController!,
                                                    widget
                                                        .store
                                                        .conflicts
                                                        .length,
                                                  ),
                                            onTap: widget.onSyncStatus ?? () {},
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.store.summaries.isNotEmpty)
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _PinnedSearch(
                          height: searchHeight,
                          child: ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: wide ? _wideToolbar() : _search(),
                            ),
                          ),
                        ),
                      ),
                    if (widget.store.summaries.isNotEmpty && !wide)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: PixelSingleChildScrollView(
                            key: const Key('recipe-controls-scroll'),
                            scrollDirection: Axis.horizontal,
                            child: _controls(),
                          ),
                        ),
                      ),
                    if (widget.store.setAsideCount > 0)
                      SliverToBoxAdapter(child: _setAsideNotice()),
                    if (widget.store.error != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text('Recipes could not be refreshed'),
                              ),
                              TextButton(
                                onPressed: widget.store.refresh,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (widget.store.loading && widget.store.summaries.isEmpty)
                      const SliverFillRemaining(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (recipes.isEmpty && widget.store.error == null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: widget.store.summaries.isEmpty
                            ? _emptyLibrary(context, constraints.maxWidth)
                            : Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'No matching recipes',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      const SizedBox(height: 16),
                                      TextButton(
                                        onPressed:
                                            widget.preferences.resetSearch,
                                        child: const Text('Reset'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                    if (recipes.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                        sliver: SliverList.builder(
                          itemCount: (recipes.length / columns).ceil(),
                          findChildIndexCallback: (key) =>
                              key is ValueKey<String>
                              ? rowIndices[key.value]
                              : null,
                          itemBuilder: (context, row) => Padding(
                            key: ValueKey('group-${recipes[row * columns].id}'),
                            padding: EdgeInsets.only(
                              bottom:
                                  widget.preferences.view == RecipeView.cards
                                  ? 10
                                  : 0,
                            ),
                            child: RecipeGridRow(
                              columns: columns,
                              fixedHeight: cardHeight,
                              children: [
                                for (var col = 0; col < columns; col++)
                                  if (row * columns + col < recipes.length)
                                    _row(
                                      recipes[row * columns + col],
                                      grid: grid,
                                    ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (widget.store.summaries.isNotEmpty && widget.selectedIds == null)
              Positioned(
                right: 16,
                bottom: 16,
                child: ValueListenableBuilder(
                  valueListenable: _showAdd,
                  builder: (_, visible, child) =>
                      ScrollAwareFab(visible: visible, child: child!),
                  child: FloatingActionButton(
                    key: const Key('add-recipe'),
                    tooltip: 'Add recipe',
                    onPressed: widget.onAdd,
                    child: const Icon(Symbols.add),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );

  Future<void> _favorite(RecipeSummary recipe) async {
    try {
      await widget.store.toggleFavorite(recipe.id);
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Could not update favorite',
          kind: FeedbackKind.error,
        );
      }
    }
  }
}

class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    super.key,
    required this.recipe,
    required this.view,
    required this.grid,
    required this.onOpen,
    required this.onActions,
    required this.onFavorite,
    required this.selecting,
    required this.selected,
  });
  final RecipeSummary recipe;
  final RecipeView view;
  final bool grid;
  final bool selecting, selected;
  final ValueChanged<String> onOpen;
  final ValueChanged<RecipeSummary> onActions;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = view == RecipeView.compact;
    final star = selecting
        ? SizedBox(
            width: 48,
            height: 48,
            child: Checkbox(
              value: selected,
              semanticLabel: 'Select ${recipe.title}',
              onChanged: (_) => onOpen(recipe.id),
            ),
          )
        : IconButton(
            tooltip: recipe.favorite
                ? 'Unfavorite ${recipe.title}'
                : 'Favorite ${recipe.title}',
            onPressed: onFavorite,
            icon: Icon(
              Symbols.star,
              fill: recipe.favorite ? 1 : 0,
              color: recipe.favorite
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          );
    final title = Text(
      recipe.title,
      maxLines: compact ? 1 : 3,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    final metadata = RecipeMetadata(
      servings: recipe.servings,
      totalTime: recipe.totalTime,
      prepTime: recipe.prepTime,
      cookTime: recipe.cookTime,
      singleLine: grid,
    );
    return Material(
      color: view == RecipeView.cards
          ? theme.colorScheme.surfaceContainer
          : Colors.transparent,
      borderRadius: BorderRadius.circular(compact ? 0 : 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(recipe.id),
        onLongPress: () => onActions(recipe),
        onSecondaryTap: () => onActions(recipe),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              title,
                              if (recipe.tags.isNotEmpty)
                                Text(
                                  normalizeTags(recipe.tags).join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 48, child: star),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
              )
            : grid
            ? Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 44),
                          child: RecipeCardTextBudget(
                            title: recipe.title,
                            description: recipe.description,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: recipeMetadataLineHeight(context),
                          child: metadata,
                        ),
                        const SizedBox(height: 8),
                        // Empty tags reserve the same footer slot as populated cards.
                        SizedBox(
                          height: recipeGridTagHeight(context),
                          child: RecipeTagLine(recipe.tags),
                        ),
                      ],
                    ),
                    Positioned(right: -10, top: 0, child: star),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Stack(
                    fit: StackFit.passthrough,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 54),
                        child: RecipeCardContent(
                          title: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              if (recipe.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    recipe.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          metadata: metadata.isEmpty
                              ? const SizedBox.shrink()
                              : metadata,
                          tags: recipe.tags.isEmpty
                              ? const SizedBox.shrink()
                              : RecipeTagLine(recipe.tags),
                        ),
                      ),
                      Positioned(right: 0, top: 0, child: star),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _PinnedSearch extends SliverPersistentHeaderDelegate {
  _PinnedSearch({required this.height, required this.child});
  final double height;
  final Widget child;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SizedBox.expand(child: child);
  @override
  bool shouldRebuild(_PinnedSearch oldDelegate) =>
      oldDelegate.height != height || oldDelegate.child != child;
}

String _fieldLabel(SearchField field) => switch (field) {
  SearchField.title => 'Title',
  SearchField.ingredients => 'Ingredients',
  SearchField.tags => 'Tags',
  SearchField.notes => 'Notes',
  SearchField.description => 'Description',
};
String _sortLabel(RecipeSort sort) => switch (sort) {
  RecipeSort.edited => 'Recently edited',
  RecipeSort.added => 'Recently added',
  RecipeSort.title => 'Title',
};
