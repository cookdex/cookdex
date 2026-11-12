import 'page_headings.dart';

import 'dart:async';
import 'dart:math' as math;

import 'pixel_scroll.dart';
import 'idle_build_ahead.dart';
import 'progressive_cards.dart';
import 'prepared_card_title.dart';
import 'recipe_top_button.dart';
import 'facelift_motion.dart';
import 'facelift_tokens.dart';
import 'top_return_sliver.dart';
import 'retained_screen.dart';
import '../sync_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../local_preferences.dart';
import '../recipe_store.dart';
import '../tag_labels.dart';
import '../src/rust/api.dart';
import 'components.dart';
import 'feedback.dart';
import 'recipe_filters.dart';
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
    this.onDesignLab,
    this.keyboardVisible = false,
    this.onWrite,
    this.onImport,
    this.onCreate,
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
    this.onDeleteSelection,
    this.onTagSelection,
  });

  /// Null means normal browsing; an empty set keeps selection mode active.
  final Set<String>? selectedIds;
  final ValueChanged<String>? onToggleSelection;
  final VoidCallback? onCloseSelection,
      onSelectAll,
      onShareSelection,
      onShoppingSelection,
      onDeleteSelection,
      onTagSelection;
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
  final VoidCallback? onImport, onDesignLab;
  final VoidCallback? onCreate;
  final bool keyboardVisible;
  final Future<void> Function()? onSync;

  @override
  State<RecipesScreen> createState() => RecipesScreenState();
}

class RecipesScreenState extends State<RecipesScreen> {
  Widget _heading(Widget title) => Semantics(
    button: true,
    label: 'cookdex, Back to top',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: scrollToTop,
      onLongPress: widget.onDesignLab,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(alignment: Alignment.centerLeft, child: title),
        ),
      ),
    ),
  );
  late final TextEditingController _query;
  late String _resultsQuery;
  int _queryChange = 0;
  bool _positioningResults = false;
  late final ScrollController _scroll;
  bool _topAllowed = true;
  final _showTop = ValueNotifier(false);
  final _topSliver = GlobalKey();
  ScrollPosition? _topPosition;
  double _topOffset = 0;
  int _topJump = 0;
  bool _returningTop = false, _listMoving = false;
  double _topLow = 0, _topHigh = 0;
  Timer? _topIdle;
  final Map<String, _RecipeRow> _rows = {};
  final _builtCards = BuiltRowBudget(32);
  final _cardPreparation = CardPreparation();
  Widget? _list;
  List<RecipeSummary>? _listRecipes;
  int? _listColumns;
  double? _listHeight;
  RecipeView? _listView;
  Set<String>? _listSelection;
  int? _listPartialStart;

  Widget _recipeList(
    List<RecipeSummary> recipes,
    int columns,
    double? cardHeight,
  ) {
    if (_list != null &&
        identical(recipes, _listRecipes) &&
        columns == _listColumns &&
        cardHeight == _listHeight &&
        _listPartialStart == widget.store.partialMatchStart &&
        widget.preferences.view == _listView &&
        setEquals(widget.selectedIds, _listSelection)) {
      return _list!;
    }
    _listRecipes = recipes;
    _listColumns = columns;
    _listHeight = cardHeight;
    _listPartialStart = widget.store.partialMatchStart;
    _listView = widget.preferences.view;
    _listSelection = widget.selectedIds == null
        ? null
        : Set.of(widget.selectedIds!);
    final view = widget.preferences.view;
    // Unsupported accessibility typography uses natural full-card sizing in
    // the same columns, without the standard grid's fixed text/footer slots.
    final grid =
        columns > 1 &&
        view == RecipeView.cards &&
        CardGeometryCache.supports(context);
    // A partial group starts on its own grid row. The header sits outside the
    // card/shell geometry, with its full natural height from the first layout.
    final groups = <({int start, int end})>[];
    for (var start = 0; start < recipes.length;) {
      var end = math.min(start + columns, recipes.length);
      if (_listPartialStart case final split?
          when start < split && end > split) {
        end = split;
      }
      groups.add((start: start, end: end));
      start = end;
    }
    final rowIndices = <String, int>{
      for (var i = 0; i < groups.length; i++)
        'group-${recipes[groups[i].start].id}': i,
    };
    return _list = SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
      sliver: TopReturnSliverList.builder(
        key: _topSliver,
        itemCount: groups.length,
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? rowIndices[key.value] : null,
        itemBuilder: (context, row) {
          Widget child = Padding(
            padding: EdgeInsets.only(bottom: view == RecipeView.cards ? 10 : 0),
            child: RecipeGridRow(
              columns: columns,
              fixedHeight: cardHeight,
              children: [
                for (
                  var index = groups[row].start;
                  index < groups[row].end;
                  index++
                )
                  _row(recipes[index], grid: grid),
              ],
            ),
          );
          if (groups[row].start == _listPartialStart) {
            child = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 8),
                  child: Semantics(
                    container: true,
                    header: true,
                    child: Text(
                      _listPartialStart == 0
                          ? 'No recipes match every word.\nThese match some of them.'
                          : 'Partial matches',
                      key: const Key('partial-matches'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                child,
              ],
            );
          }
          return KeepBuilt(
            key: ValueKey('group-${recipes[groups[row].start].id}'),
            enabled: view == RecipeView.cards,
            budget: _builtCards,
            weight: columns,
            child: child,
          );
        },
      ),
    );
  }

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
      onOpen: (id) {
        if (widget.selectedIds != null) {
          widget.onToggleSelection?.call(id);
        } else {
          _cardPreparation.pauseForNavigation();
          widget.onOpenRecipe(id);
        }
      },
      onActions: (value) {
        widget.onActions(value);
      },
      onFavorite: () => _favorite(recipe),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
      if (mounted) widget.store.prepareRecipeSearch();
    });
    _query = TextEditingController(text: widget.preferences.query);
    _resultsQuery = widget.preferences.query.trim();
    _scroll =
        widget.controller ??
        PixelScrollController(
          initialScrollOffset: widget.preferences.scrollOffset,
        );
    _scroll.addListener(_saveScroll);
    _scroll.addListener(_updateTop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateTop();
    });
    widget.preferences.addListener(_syncQuery);
  }

  void _saveScroll() {
    if (!_positioningResults) {
      widget.preferences.setScrollOffset(_scroll.offset);
    }
  }

  void _updateTop() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (!identical(_topPosition, position)) {
      _topPosition?.isScrollingNotifier.removeListener(_updateTop);
      _topPosition = position;
      position.isScrollingNotifier.addListener(_updateTop);
      _topOffset = position.pixels;
    }
    final offset = position.pixels;
    final moving = position.isScrollingNotifier.value;
    if (moving && !_listMoving) _topLow = _topHigh = _topOffset;
    _topOffset = offset;
    _listMoving = moving;
    if (moving) {
      _topIdle?.cancel();
      _topIdle = null;
      _topLow = math.min(_topLow, offset);
      _topHigh = math.max(_topHigh, offset);
      // A card-sized downward excursion hides Top. A small, intentional upward
      // movement restores it; jitter cannot flip it repeatedly.
      if (_topAllowed && offset - _topLow >= 200) {
        _topAllowed = false;
        _topHigh = offset;
      } else if (!_topAllowed && _topHigh - offset >= 24) {
        _topAllowed = true;
        _topLow = offset;
      }
    } else {
      _topIdle ??= Timer(const Duration(milliseconds: 500), () {
        _topIdle = null;
        if (!mounted || !_scroll.hasClients) return;
        _topLow = _topHigh = _scroll.offset;
        _topAllowed = true;
        _syncTopVisibility();
      });
    }
    if (offset <= 24) _topAllowed = true;
    _syncTopVisibility();
  }

  void _syncTopVisibility() {
    _showTop.value =
        !_returningTop &&
        _topAllowed &&
        _scroll.hasClients &&
        _scroll.offset > _scroll.position.viewportDimension * 2;
  }

  Future<void> scrollToTop() async {
    if (!_scroll.hasClients || _scroll.offset <= 0 || _returningTop) return;
    final jump = ++_topJump;
    _returningTop = true;
    _showTop.value = false;
    _cardPreparation.jumping = true;
    try {
      if (MediaQuery.disableAnimationsOf(context)) {
        _restartTopSliver();
        _scroll.jumpTo(0);
      } else {
        final start = _scroll.offset;
        final viewport = _scroll.position.viewportDimension;
        final departure = math.min(start * .45, viewport * .9);
        final landing = math.min(start - departure, viewport * .7);
        _cardPreparation.prepareTopReturn(viewport + landing);
        await _scroll.animateTo(
          start - departure,
          duration: FaceliftMotion.topDeparture,
          curve: Easing.emphasizedAccelerate,
        );
        if (!mounted ||
            jump != _topJump ||
            !_scroll.hasClients ||
            (_scroll.offset - (start - departure)).abs() > 1) {
          return;
        }
        // Only the unseen middle is skipped, at the fastest point of the trip.
        if (_scroll.offset > landing) {
          if (_scroll.offset - landing > viewport) _restartTopSliver();
          _scroll.jumpTo(landing);
        }
        await _scroll.animateTo(
          0,
          duration: FaceliftMotion.topLanding,
          curve: Easing.emphasizedDecelerate,
        );
      }
    } finally {
      if (mounted && jump == _topJump) {
        _returningTop = false;
        _cardPreparation.finishTopReturn();
        _updateTop();
      }
    }
  }

  void _restartTopSliver() {
    final render = _topSliver.currentContext?.findRenderObject();
    if (render is RenderTopReturnSliverList) render.restartAtTop();
  }

  void _interruptTop() {
    if (!_returningTop) return;
    _topJump++;
    _returningTop = false;
    _cardPreparation.finishTopReturn();
  }

  KeyEventResult _listKey(FocusNode node, KeyEvent event) {
    if (Theme.of(context).platform == TargetPlatform.windows &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.home &&
        FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<EditableText>() ==
            null) {
      scrollToTop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _syncQuery() {
    if (_query.text != widget.preferences.query) {
      _query.value = TextEditingValue(
        text: widget.preferences.query,
        selection: TextSelection.collapsed(
          offset: widget.preferences.query.length,
        ),
      );
    }
    final query = widget.preferences.query.trim();
    if (query != _resultsQuery) {
      _resultsQuery = query;
      final change = ++_queryChange;
      _positioningResults = true;
      _interruptTop();
      final offset = widget.preferences.scrollOffset;
      if (offset == 0 && _scroll.hasClients && _scroll.offset != 0) {
        _restartTopSliver();
        _scroll.jumpTo(0);
      }
      // Clearing a short or empty result must wait for the full list's extent.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || change != _queryChange) return;
        _positioningResults = false;
        if (!_scroll.hasClients) return;
        final target = offset.clamp(0.0, _scroll.position.maxScrollExtent);
        if (_scroll.offset != target) _scroll.jumpTo(target);
        _saveScroll();
      });
    } else if (!_positioningResults &&
        widget.preferences.scrollOffset == 0 &&
        _scroll.hasClients &&
        _scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _topIdle?.cancel();
    _topJump++;
    widget.preferences.removeListener(_syncQuery);
    _scroll.removeListener(_saveScroll);
    _scroll.removeListener(_updateTop);
    _topPosition?.isScrollingNotifier.removeListener(_updateTop);
    if (widget.controller == null) _scroll.dispose();
    _query.dispose();
    _showTop.dispose();
    _cardPreparation.dispose();
    super.dispose();
  }

  Future<void> _fields() => showRecipeSearchFields(context, widget.preferences);

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FaceliftTokens.filterRadius),
      ),
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

  Widget _selectionBar() => LayoutBuilder(
    builder: (context, constraints) {
      final count = '${widget.selectedIds!.length} selected';
      final style = Theme.of(context).textTheme.titleMedium!;
      final measure = TextPainter(
        text: TextSpan(text: count, style: style),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      final labelWidth = measure.width.ceilToDouble();
      measure.dispose();
      final empty = widget.selectedIds!.isEmpty;
      // First entries move into the menu first. Each action retains 48dp.
      final actions = [
        ('Select all', Symbols.select_all, widget.onSelectAll),
        (
          'Share selected recipes',
          Symbols.share,
          empty ? null : widget.onShareSelection,
        ),
        ('Add tag', Symbols.label, empty ? null : widget.onTagSelection),
        (
          'Add selected recipes to shopping list',
          Symbols.shopping_cart,
          empty ? null : widget.onShoppingSelection,
        ),
        (
          'Delete selected recipes',
          Symbols.delete,
          empty ? null : widget.onDeleteSelection,
        ),
      ];
      final slots = ((constraints.maxWidth - labelWidth - 48 - 8) / 48).floor();
      final visible = slots >= actions.length
          ? actions.length
          : (slots - 1).clamp(0, actions.length);
      final hidden = actions.length - visible;
      Icon symbol(IconData icon) => Icon(
        icon,
        color: icon == Symbols.delete
            ? mutedDeleteColor(Theme.of(context).colorScheme)
            : null,
      );
      return Row(
        children: [
          IconButton(
            tooltip: 'Close selection',
            onPressed: widget.onCloseSelection,
            icon: const Icon(Symbols.close),
          ),
          Expanded(
            child: Text(
              count,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final (name, icon, callback) in actions.skip(hidden))
            IconButton(tooltip: name, onPressed: callback, icon: symbol(icon)),
          if (hidden > 0)
            MenuAnchor(
              style: MenuStyle(
                alignment: AlignmentDirectional.bottomEnd,
                maximumSize: WidgetStatePropertyAll(
                  Size(constraints.maxWidth, double.infinity),
                ),
              ),
              menuChildren: [
                for (final (name, icon, callback) in actions.take(hidden))
                  MenuItemButton(
                    leadingIcon: symbol(icon),
                    onPressed: callback,
                    child: Text(switch (icon) {
                      Symbols.share => 'Share',
                      Symbols.shopping_cart => 'Add to list',
                      Symbols.delete => 'Delete',
                      _ => name,
                    }),
                  ),
              ],
              builder: (_, controller, _) => IconButton(
                tooltip: 'More selection actions',
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
                icon: const Icon(Symbols.more_vert),
              ),
            ),
        ],
      );
    },
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FaceliftTokens.filterRadius),
        ),
        label: const Text('Favorites'),
        avatar: Icon(
          Symbols.star,
          fill: widget.preferences.favoritesOnly ? 1 : 0,
          color: theme.colorScheme.tertiary,
          size: 18,
        ),
        selectedColor: theme.colorScheme.tertiaryContainer,
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
      textCapitalization: TextCapitalization.none,
      scrollController: PrimaryScrollController.of(context),
      key: const Key('recipe-search'),
      controller: _query,
      onChanged: widget.preferences.setQuery,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search recipes',
        prefixIcon: const Icon(Symbols.search),
        suffixIcon: SearchFieldActions(
          controller: _query,
          onClear: () => widget.preferences.setQuery(''),
          onOptions: _fields,
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
      style: FilledButton.styleFrom(
        backgroundColor: theme.colorScheme.tertiary,
        foregroundColor: theme.colorScheme.onTertiary,
      ),
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
                  if (widget.onCreate != null)
                    TextButton.icon(
                      onPressed: widget.onCreate,
                      icon: const Icon(Symbols.lightbulb),
                      label: const Text('Smart Create'),
                    ),
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
        final grid =
            columns > 1 &&
            widget.preferences.view == RecipeView.cards &&
            CardGeometryCache.supports(context);
        final cardHeight = grid ? recipeGridCardHeight(context) : null;
        if (widget.preferences.view == RecipeView.cards) {
          _cardPreparation.configure(
            context,
            recipes,
            recipeGridColumnWidth(constraints.maxWidth - 32, columns),
            grid: grid,
            fixedHeight: cardHeight,
            columns: columns,
          );
        }
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final searchHeight = 64.0 + (scale - 1).clamp(0, 3) * 24;
        final wide = MediaQuery.sizeOf(context).width >= 600;
        return Stack(
          children: [
            Focus(
              debugLabel: 'Recipes list',
              onKeyEvent: _listKey,
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (notification) {
                  if (notification.depth == 0 &&
                      notification.dragDetails != null) {
                    _interruptTop();
                  }
                  return false;
                },
                child: RefreshIndicator(
                  onRefresh: widget.onSync ?? () async {},
                  child: _RecipeScrollView(
                    preparation: _cardPreparation,
                    enabled: widget.preferences.view == RecipeView.cards,
                    controller: _scroll,
                    slivers: [
                      SliverPersistentHeader(
                        pinned:
                            widget.selectedIds != null ||
                            widget.syncStatus != null ||
                            widget.syncController != null,
                        delegate: _PinnedSearch(
                          height:
                              PageHeadings.tabRowHeight(context) +
                              PageHeadings.gap,
                          child: ColoredBox(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            child: widget.selectedIds != null
                                ? Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: _selectionBar(),
                                  )
                                : TabHeading(
                                    title: _heading(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Symbols.skillet, size: 28),
                                          const SizedBox(width: 8),
                                          const Flexible(
                                            child: Text(
                                              'cookdex',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    action:
                                        widget.syncStatus != null ||
                                            widget.syncController != null
                                        ? VisibleListenableBuilder(
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
                                              onTap:
                                                  widget.onSyncStatus ?? () {},
                                            ),
                                          )
                                        : null,
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
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  8,
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
                      if (widget.store.loading &&
                          widget.store.summaries.isEmpty)
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
                                        const FaceliftIconTile(
                                          Symbols.search_off,
                                          size: 56,
                                        ),
                                        const SizedBox(height: 12),
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
                        _recipeList(recipes, columns, cardHeight),
                      if (MediaQuery.paddingOf(context).bottom > 0)
                        SliverToBoxAdapter(
                          child: SizedBox(
                            height: MediaQuery.paddingOf(context).bottom,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.selectedIds == null)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                child: Center(
                  child: RecipeTopButton(
                    visible: _showTop,
                    onPressed: scrollToTop,
                  ),
                ),
              ),
            if (widget.store.summaries.isNotEmpty &&
                widget.selectedIds == null &&
                !widget.keyboardVisible)
              Positioned(
                right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                child: ValueListenableBuilder<bool>(
                  valueListenable: feedbackVisibilityOf(context),
                  builder: (context, feedback, child) =>
                      feedback ? const SizedBox.shrink() : child!,
                  child: FloatingActionButton(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        FaceliftTokens.addRadius,
                      ),
                    ),
                    key: const Key('add-recipe'),
                    tooltip: 'Add recipe',
                    hoverColor:
                        Theme.of(context).platform == TargetPlatform.android
                        ? Colors.transparent
                        : null,
                    hoverElevation:
                        Theme.of(context).platform == TargetPlatform.android
                        ? 6
                        : null,
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
      unawaited(HapticFeedback.selectionClick());
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

/// Keep the sliver delegates stable while only the viewport cache grows.
class _RecipeScrollView extends StatelessWidget {
  const _RecipeScrollView({
    required this.preparation,
    required this.enabled,
    required this.controller,
    required this.slivers,
  });
  final bool enabled;
  final ScrollController controller;
  final List<Widget> slivers;
  final CardPreparation preparation;

  @override
  Widget build(BuildContext context) => ProgressiveCards(
    preparation: preparation,
    controller: controller,
    child: IdleBuildAhead(
      enabled: enabled,
      controller: controller,
      paused: preparation.paused,
      builder: (context, cache) => PixelCustomScrollView(
        key: const PageStorageKey('recipes-scroll'),
        scrollCacheExtent: ScrollCacheExtent.pixels(cache),
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    ),
  );
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
    this.forcedStage,
  });
  final RecipeSummary recipe;
  final RecipeView view;
  final bool grid;
  final bool selecting, selected;
  final int? forcedStage;
  final ValueChanged<String> onOpen;
  final ValueChanged<RecipeSummary> onActions;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) => view == RecipeView.compact
      ? _build(context, 4, null)
      : ProgressiveCard(
          recipe: recipe,
          grid: grid,
          forcedStage: forcedStage,
          builder: _build,
        );

  Widget _build(BuildContext context, int stage, CardGeometry? geometry) {
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
            onPressed: () {
              popCardStar(context, !recipe.favorite);
              onFavorite();
            },
            icon: Icon(
              Symbols.star,
              fill: recipe.favorite ? 1 : 0,
              color: recipe.favorite
                  ? theme.colorScheme.tertiary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          );
    final prepared = geometry?.title;
    final title = prepared != null
        ? PreparedCardTitle(recipe.title, prepared: prepared)
        : Text(
            recipe.title,
            maxLines: compact ? 1 : 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          );
    final metadata = RecipeMetadata(
      servings: recipe.servings,
      totalTime: recipe.totalTime,
      prepTime: recipe.prepTime,
      cookTime: recipe.cookTime,
      singleLine: grid,
      optimizeItems: !compact,
    );
    final row = InkWell(
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 44),
                        child: RecipeCardTextBudget(
                          title: recipe.title,
                          preparedTitle: prepared == null ? null : title,
                          preparedTitleLines: prepared?.painter
                              .computeLineMetrics()
                              .length
                              .clamp(1, 2),
                          description: stage >= 1 ? recipe.description : '',
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: recipeMetadataLineHeight(context),
                        child: stage >= 2 ? metadata : null,
                      ),
                      const SizedBox(height: 8),
                      // Empty tags reserve the same footer slot as populated cards.
                      SizedBox(
                        height: recipeGridTagHeight(context),
                        child: stage >= 3
                            ? RecipeTagLine(
                                recipe.tags,
                                preparedValues: geometry?.tagLabels,
                                preparedVisible: geometry?.visibleTags,
                                preparedWidth: geometry?.tagWidth,
                              )
                            : null,
                      ),
                    ],
                  ),
                  if (stage >= 4 || selecting)
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
                                child: stage < 1
                                    ? SizedBox(
                                        height: geometry!.descriptionHeight,
                                      )
                                    : Text(
                                        recipe.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                              ),
                          ],
                        ),
                        metadata: stage < 2
                            ? SizedBox(height: geometry!.metadataHeight)
                            : metadata.isEmpty
                            ? const SizedBox.shrink()
                            : metadata,
                        tags: stage < 3
                            ? SizedBox(height: geometry!.tagsHeight)
                            : recipe.tags.isEmpty
                            ? const SizedBox.shrink()
                            : RecipeTagLine(
                                recipe.tags,
                                preparedValues: geometry?.tagLabels,
                                preparedVisible: geometry?.visibleTags,
                                preparedWidth: geometry?.tagWidth,
                              ),
                      ),
                    ),
                    if (stage >= 4 || selecting)
                      Positioned(right: 0, top: 0, child: star),
                  ],
                ),
              ),
            ),
    );
    if (compact) return row;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(FaceliftTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: row,
    );
  }
}

@visibleForTesting
Widget recipeCardForTest(
  RecipeSummary recipe, {
  bool grid = false,
  bool selecting = false,
  bool selected = false,
  int? stage,
}) => _RecipeRow(
  recipe: recipe,
  view: RecipeView.cards,
  grid: grid,
  selecting: selecting,
  selected: selected,
  forcedStage: stage,
  onOpen: (_) {},
  onActions: (_) {},
  onFavorite: () {},
);

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

String _sortLabel(RecipeSort sort) => switch (sort) {
  RecipeSort.edited => 'Recently edited',
  RecipeSort.added => 'Recently added',
  RecipeSort.title => 'Title',
};
