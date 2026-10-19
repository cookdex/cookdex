import 'pixel_scroll.dart';

import 'dart:async';
import 'dart:math' as math;

import '../ingredient_display.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../recipe_store.dart';
import '../src/rust/api.dart';
import 'components.dart';
import 'feedback.dart';
import 'navigation_feedback.dart';

String _message(Object error) =>
    error is ServiceError ? error.message : 'Could not update shopping list.';

void _shoppingUndo(
  ScaffoldMessengerState messenger,
  RecipeStore store,
  ShoppingUndo undo,
  String message,
) {
  showFeedbackWithMessenger(
    messenger,
    message,
    onUndo: () async {
      try {
        await store.undoShopping(undo);
      } catch (error) {
        if (messenger.mounted) {
          showFeedbackWithMessenger(
            messenger,
            _message(error),
            kind: FeedbackKind.error,
          );
        }
      }
    },
  );
}

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({
    super.key,
    required this.store,
    required this.onSaveText,
  });
  final RecipeStore store;
  final Future<void> Function(BuildContext context) onSaveText;

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen>
    with TickerProviderStateMixin {
  static const _checkPause = Duration(milliseconds: 300);
  static const _moveDuration = Duration(milliseconds: 200);
  final _input = TextEditingController();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _busy = false;
  String? _inputError;
  bool _reduceMotion = false;
  final _placements = <String, bool>{};
  final _moves = <String, _ShoppingMove>{};
  final _arrivals = <String, Timer>{};

  @override
  void initState() {
    super.initState();
    _resetPlacements();
    widget.store.addListener(_shoppingChanged);
  }

  @override
  void didUpdateWidget(ShoppingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_shoppingChanged);
      _resetPlacements();
      widget.store.addListener(_shoppingChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _resetPlacements();
  }

  void _resetPlacements() {
    for (final move in _moves.values) {
      move.dispose();
    }
    for (final timer in _arrivals.values) {
      timer.cancel();
    }
    _moves.clear();
    _arrivals.clear();
    _placements
      ..clear()
      ..addEntries(widget.store.shopping.map((i) => MapEntry(i.id, i.checked)));
  }

  void _shoppingChanged() {
    if (!mounted) return;
    if (!TickerMode.valuesOf(context).enabled ||
        ModalRoute.isCurrentOf(context) == false) {
      _resetPlacements();
      return;
    }
    setState(() {
      final items = widget.store.shopping;
      final ids = items.map((i) => i.id).toSet();
      for (final id in _placements.keys.toList()) {
        if (!ids.contains(id)) {
          _placements.remove(id);
          _moves.remove(id)?.dispose();
          _arrivals.remove(id)?.cancel();
        }
      }
      for (final item in items) {
        _placements.putIfAbsent(item.id, () => item.checked);
        if (_reduceMotion || _placements[item.id] == item.checked) {
          _moves.remove(item.id)?.dispose();
          _placements[item.id] = item.checked;
          continue;
        }
        // Store notifications unrelated to this row must not restart its hold.
        if (_moves.containsKey(item.id)) continue;
        _arrivals.remove(item.id)?.cancel();
        final move = _ShoppingMove(
          item.checked,
          AnimationController(vsync: this, duration: _moveDuration),
        );
        move.animation.addStatusListener((status) {
          if (status == AnimationStatus.completed) _finishMove(item.id, move);
        });
        _moves[item.id] = move;
        move.timer = Timer(_checkPause, () {
          if (!mounted || _moves[item.id] != move) return;
          move.animation.forward();
        });
      }
    });
  }

  void _finishMove(String id, _ShoppingMove move) {
    if (!mounted || _moves[id] != move) return;
    setState(() {
      _moves.remove(id);
      move.dispose();
      _placements[id] = move.checked;
      _arrivals[id] = Timer(_moveDuration, () {
        if (mounted) setState(() => _arrivals.remove(id));
      });
    });
  }

  @override
  void dispose() {
    widget.store.removeListener(_shoppingChanged);
    for (final move in _moves.values) {
      move.dispose();
    }
    for (final timer in _arrivals.values) {
      timer.cancel();
    }
    _input.dispose();
    super.dispose();
  }

  Future<bool> _change(ShoppingEdit edit, [String? undoMessage]) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final undo = await widget.store.editShopping(edit);
      if (mounted && undoMessage != null) {
        _shoppingUndo(
          _messenger.currentState!,
          widget.store,
          undo,
          undoMessage,
        );
      }
      return true;
    } catch (error) {
      if (mounted) {
        showFeedbackWithMessenger(
          _messenger.currentState!,
          _message(error),
          kind: FeedbackKind.error,
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    final text = _input.text;
    if (text.trim().isEmpty) {
      setState(() => _inputError = 'Enter an item.');
      return;
    }
    setState(() => _inputError = null);
    if (await _change(ShoppingEdit.addManual(text: text)) && mounted) {
      if (_input.text == text) _input.clear();
    }
  }

  Future<void> _edit(ShoppingItem item) async {
    if (_busy) return;
    await showDialog<ShoppingUndo>(
      context: context,
      builder: (_) => _EditShoppingDialog(store: widget.store, item: item),
    );
  }

  Future<void> _itemMenu(ShoppingItem item) async {
    if (_busy || _moves.containsKey(item.id)) return;
    final choice = await showCookdexSheet<String>(
      context,
      child: Builder(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Edit'),
              leading: const Icon(Symbols.edit),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              title: const Text('Move to category'),
              leading: const Icon(Symbols.drive_file_move),
              onTap: () => Navigator.pop(context, 'move'),
            ),
            ListTile(
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              leading: Icon(
                Symbols.delete,
                color: Theme.of(context).colorScheme.error,
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'delete') {
      await _change(ShoppingEdit.remove(ids: [item.id]), 'Item removed');
      return;
    }
    if (choice == 'edit') await _edit(item);
    if (choice != 'move' || !mounted) return;
    final categoryId = await showCookdexSheet<String>(
      context,
      child: Builder(
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Move to category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            for (final category in widget.store.shoppingCategories)
              ListTile(
                title: Text(category.name),
                trailing: category.id == item.categoryId
                    ? const Icon(Symbols.check)
                    : null,
                onTap: () => Navigator.pop(context, category.id),
              ),
          ],
        ),
      ),
    );
    if (mounted && categoryId != null && categoryId != item.categoryId) {
      await _change(ShoppingEdit.move(id: item.id, categoryId: categoryId));
    }
  }

  Widget _categoryHeading(
    String categoryId,
    String name,
    List<ShoppingItem> items,
  ) => TweenAnimationBuilder<double>(
    key: ValueKey('shopping-heading-$categoryId'),
    tween: Tween(
      begin: items.every((item) => _arrivals.containsKey(item.id)) ? 0 : 1,
      end: 1,
    ),
    duration: _reduceMotion ? Duration.zero : _moveDuration,
    builder: (context, arrival, child) => AnimatedBuilder(
      animation: Listenable.merge([
        for (final item in items)
          if (_moves[item.id] != null) _moves[item.id]!.animation,
      ]),
      builder: (context, child) {
        final departing = items.every(
          (item) => _moves[item.id]?.checked == true,
        );
        final departure = departing
            ? items
                  .map((item) => _moves[item.id]!.animation.value)
                  .reduce((a, b) => a < b ? a : b)
            : 0.0;
        final value =
            arrival * (1 - Curves.easeInOutCubic.transform(departure));
        return ClipRect(
          child: Align(
            alignment: Alignment.topLeft,
            heightFactor: value,
            child: Opacity(opacity: value, child: child),
          ),
        );
      },
      child: child,
    ),
    child: _categoryBand(name, items),
  );

  Widget _categoryBand(String name, List<ShoppingItem> items) {
    final theme = Theme.of(context);
    final count = items.where((item) => !item.checked).length;
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Semantics(
        header: true,
        label: '$name, $count unchecked',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '$count',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reorderShopping(
    List<_ShoppingEntry> entries,
    int oldIndex,
    int newIndex,
  ) {
    if (_busy || _moves.isNotEmpty || oldIndex == newIndex) return;
    final item = entries[oldIndex].item;
    if (item == null) return;
    final reordered = entries.toList();
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    // A drop before the first heading means the first item in that category.
    var destination = entries.first.categoryId;
    for (var i = 0; i < newIndex; i++) {
      if (reordered[i].item == null) destination = reordered[i].categoryId;
    }
    if (destination == item.categoryId) {
      final ids = [
        for (final entry in reordered)
          if (entry.item != null && entry.categoryId == destination)
            entry.item!.id,
      ];
      _change(ShoppingEdit.reorderItems(categoryId: destination, ids: ids));
    } else {
      String? beforeId;
      for (final entry in reordered.skip(newIndex + 1)) {
        if (entry.item != null && entry.categoryId == destination) {
          beforeId = entry.item!.id;
          break;
        }
      }
      _change(
        ShoppingEdit.move(
          id: item.id,
          categoryId: destination,
          beforeId: beforeId,
        ),
      );
    }
  }

  Future<void> _menu(String choice) async {
    if (_busy) return;
    final items = widget.store.shopping;
    switch (choice) {
      case 'categories':
        await Navigator.of(context).push(
          cookdexRoute<void>(
            context,
            builder: (_) => _ShoppingCategories(store: widget.store),
          ),
        );
        if (mounted) setState(_resetPlacements);
      case 'check':
      case 'uncheck':
        final checked = choice == 'check';
        final ids = items
            .where((item) => item.checked != checked)
            .map((item) => item.id)
            .toList();
        if (ids.isEmpty) return;
        await _change(
          ShoppingEdit.check(ids: ids, checked: checked),
          checked ? 'All items checked' : 'All items unchecked',
        );
      case 'checked':
        final ids = items.where((i) => i.checked).map((i) => i.id).toList();
        if (ids.isNotEmpty) {
          await _change(ShoppingEdit.remove(ids: ids), 'Checked items cleared');
        }
      case 'save':
        setState(() => _busy = true);
        try {
          await widget.onSaveText(_scaffold.currentContext!);
        } catch (error) {
          if (mounted) {
            showFeedbackWithMessenger(
              _messenger.currentState!,
              error is ServiceError
                  ? error.message
                  : 'Could not save shopping list.',
              kind: FeedbackKind.error,
            );
          }
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      case 'clear':
        if (!await confirmCookdex(
          context,
          title: 'Clear entire shopping list?',
          action: 'Clear',
          destructive: true,
        )) {
          return;
        }
        if (!mounted) return;
        final ids = widget.store.shopping.map((i) => i.id).toList();
        if (ids.isNotEmpty) {
          await _change(ShoppingEdit.remove(ids: ids), 'Shopping list cleared');
        }
    }
  }

  String? _source(ShoppingItem item) {
    final ids = item.contributorIds.toSet();
    if (ids.isEmpty) return null;
    final titles = {
      for (final recipe in widget.store.summaries) recipe.id: recipe.title,
    };
    final visible = ids.take(2).map((id) => titles[id] ?? 'Recipe').join(', ');
    return ids.length > 2 ? '$visible +${ids.length - 2} more' : visible;
  }

  Widget _row(ShoppingItem item, {int? dragIndex}) {
    final source = _source(item);
    final theme = Theme.of(context);
    final decoration = item.checked ? TextDecoration.lineThrough : null;
    final enabled = !_busy && !_moves.containsKey(item.id);
    return GestureDetector(
      key: ValueKey(item.id),
      onSecondaryTap: enabled ? () => _itemMenu(item) : null,
      child: MergeSemantics(
        child: Semantics(
          checked: item.checked,
          enabled: enabled,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            minTileHeight: source == null ? 48 : 60,
            minVerticalPadding: 6,
            minLeadingWidth: 24,
            horizontalTitleGap: 12,
            titleAlignment: ListTileTitleAlignment.center,
            trailing: dragIndex == null
                ? null
                : _shoppingDrag(
                    dragIndex,
                    'Reorder ${item.name}',
                    enabled && _moves.isEmpty,
                  ),
            leading: ExcludeSemantics(
              child: Icon(
                item.checked
                    ? Symbols.check_box
                    : Symbols.check_box_outline_blank,
              ),
            ),
            title: Text.rich(
              key: ValueKey('shopping-item-label-${item.id}'),
              TextSpan(
                children: [
                  if (item.quantityText.isNotEmpty)
                    TextSpan(text: '${item.quantityText} '),
                  TextSpan(
                    text: item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.normal,
                decoration: decoration,
              ),
            ),
            subtitle: source == null
                ? null
                : Text(
                    source,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      decoration: decoration,
                    ),
                  ),
            onTap: !enabled
                ? null
                : () => _change(
                    ShoppingEdit.check(ids: [item.id], checked: !item.checked),
                  ),
            onLongPress: enabled ? () => _itemMenu(item) : null,
          ),
        ),
      ),
    );
  }

  Widget _animatedRow(ShoppingItem item, {int? dragIndex}) =>
      TweenAnimationBuilder<double>(
        key: ValueKey('shopping-row-${item.id}-${_placements[item.id]}'),
        tween: Tween(begin: _arrivals.containsKey(item.id) ? 0 : 1, end: 1),
        duration: _reduceMotion ? Duration.zero : _moveDuration,
        curve: Curves.easeInOutCubic,
        builder: (context, arrival, child) => AnimatedBuilder(
          animation:
              _moves[item.id]?.animation ?? const AlwaysStoppedAnimation(0.0),
          builder: (context, child) {
            final departure = _moves[item.id]?.animation.value ?? 0.0;
            final value =
                arrival * (1 - Curves.easeInOutCubic.transform(departure));
            return ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: value,
                child: Opacity(opacity: value, child: child),
              ),
            );
          },
          child: child,
        ),
        child: Column(
          children: [
            _row(item, dragIndex: dragIndex),
            const Divider(),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = widget.store.shopping;
    final checked = items.where((i) => _placements[i.id] == true).toList();
    final unchecked = items.where((i) => _placements[i.id] != true).toList();
    final entries = <_ShoppingEntry>[];
    for (final category in widget.store.shoppingCategories) {
      final rows = unchecked
          .where((item) => item.categoryId == category.id)
          .toList();
      if (rows.isEmpty) continue;
      entries.add((
        categoryId: category.id,
        name: category.name,
        items: rows,
        item: null,
      ));
      for (final item in rows) {
        entries.add((
          categoryId: category.id,
          name: category.name,
          items: rows,
          item: item,
        ));
      }
    }

    return ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        key: _scaffold,
        appBar: AppBar(
          title: const Text('Shopping list'),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Symbols.more_vert),
              tooltip: 'Shopping list options',
              enabled: !_busy,
              onSelected: _menu,
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'categories',
                  child: Text('Categories'),
                ),
                PopupMenuItem(
                  value: 'check',
                  enabled: items.any((item) => !item.checked),
                  child: const Text('Check all'),
                ),
                PopupMenuItem(
                  value: 'uncheck',
                  enabled: items.any((item) => item.checked),
                  child: const Text('Uncheck all'),
                ),
                PopupMenuItem(
                  value: 'checked',
                  enabled: items.any((item) => item.checked),
                  child: const Text('Clear checked'),
                ),
                PopupMenuItem(
                  value: 'save',
                  enabled: items.isNotEmpty,
                  child: const Text('Save list as text'),
                ),
                PopupMenuItem(
                  value: 'clear',
                  enabled: items.isNotEmpty,
                  child: Text(
                    'Clear entire list',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Your shopping list is empty'))
                    : PixelCustomScrollView(
                        slivers: [
                          _PinnedShoppingCategories(
                            entries: entries,
                            bands: [
                              for (final entry in entries)
                                if (entry.item == null)
                                  SliverToBoxAdapter(
                                    key: ValueKey(
                                      'pinned-shopping-${entry.categoryId}',
                                    ),
                                    child: _categoryHeading(
                                      entry.categoryId,
                                      entry.name,
                                      entry.items,
                                    ),
                                  ),
                            ],
                            sliver: SliverReorderableList(
                              key: const ValueKey('unchecked-shopping-items'),
                              itemCount: entries.length,
                              onReorderStart: (_) =>
                                  HapticFeedback.lightImpact(),
                              proxyDecorator: (child, index, animation) =>
                                  Material(child: child),
                              itemBuilder: (_, index) {
                                final entry = entries[index];
                                return entry.item == null
                                    ? _categoryHeading(
                                        entry.categoryId,
                                        entry.name,
                                        entry.items,
                                      )
                                    : _animatedRow(
                                        entry.item!,
                                        dragIndex: index,
                                      );
                              },
                              onReorderItem: (oldIndex, newIndex) =>
                                  _reorderShopping(entries, oldIndex, newIndex),
                            ),
                          ),
                          if (checked.isNotEmpty)
                            SliverToBoxAdapter(
                              child: ExpansionTile(
                                key: const PageStorageKey(
                                  'checked-shopping-items',
                                ),
                                title: Text('Checked (${checked.length})'),
                                initiallyExpanded: false,
                                expansionAnimationStyle: _reduceMotion
                                    ? AnimationStyle.noAnimation
                                    : const AnimationStyle(
                                        duration: _moveDuration,
                                        reverseDuration: _moveDuration,
                                        curve: Curves.easeInOutCubic,
                                      ),
                                children: [
                                  for (final item in checked)
                                    _animatedRow(item),
                                ],
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              8,
              8 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: PixelScrollScope(
                    axis: Axis.horizontal,
                    builder: (context) => TextField(
                      scrollController: PrimaryScrollController.of(context),
                      controller: _input,
                      textCapitalization: TextCapitalization.none,
                      readOnly: _busy,
                      decoration: InputDecoration(
                        hintText: 'Add an item',
                        errorText: _inputError,
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        if (_inputError != null) {
                          setState(() => _inputError = null);
                        }
                      },
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add item',
                  onPressed: _busy ? null : _add,
                  icon: const Icon(Symbols.add),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _shoppingDrag(int index, String label, bool enabled) =>
    ReorderableDelayedDragStartListener(
      index: index,
      enabled: enabled,
      child: Tooltip(
        message: 'Hold to reorder',
        triggerMode: TooltipTriggerMode.manual,
        child: Semantics(
          label: label,
          child: Container(
            width: 48,
            height: 48,
            color: Colors.transparent,
            child: const Icon(Symbols.drag_handle),
          ),
        ),
      ),
    );

class _ShoppingCategories extends StatefulWidget {
  const _ShoppingCategories({required this.store});
  final RecipeStore store;
  @override
  State<_ShoppingCategories> createState() => _ShoppingCategoriesState();
}

class _ShoppingCategoriesState extends State<_ShoppingCategories> {
  bool _busy = false;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  Future<void> _change(ShoppingEdit edit) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.store.editShopping(edit);
    } catch (error) {
      if (mounted) {
        showFeedbackWithMessenger(
          _messenger.currentState!,
          _message(error),
          kind: FeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _name({String? id, String name = ''}) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _CategoryNameDialog(store: widget.store, id: id, name: name),
    );
  }

  Future<void> _delete(String id, String name) async {
    final fallback = widget.store.shoppingCategories
        .firstWhere((c) => c.id == 'other')
        .name;
    if (!await confirmCookdex(
          context,
          title: 'Delete $name?',
          action: 'Delete',
          destructive: true,
          content: Text(
            'Items in this category and remembered ingredient choices will move to $fallback.',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _change(ShoppingEdit.deleteCategory(id: id));
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    key: _messenger,
    child: PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Categories')),
        body: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) {
              final categories = widget.store.shoppingCategories;
              return PixelCustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Text(
                        'Hold handles to reorder. Empty categories stay hidden.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: categories.length,
                    onReorderStart: (_) => HapticFeedback.lightImpact(),
                    proxyDecorator: (child, index, animation) =>
                        Material(child: child),
                    onReorderItem: (a, b) {
                      final ids = categories.map((c) => c.id).toList();
                      ids.insert(b, ids.removeAt(a));
                      _change(ShoppingEdit.reorderCategories(ids: ids));
                    },
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return ListTile(
                        key: ValueKey(category.id),
                        minTileHeight: 56,
                        contentPadding: const EdgeInsets.only(
                          left: 16,
                          right: 8,
                        ),
                        title: Text(category.name),
                        subtitle: category.id == 'other'
                            ? const Text('Default category · cannot be deleted')
                            : null,
                        onTap: _busy
                            ? null
                            : () => _name(id: category.id, name: category.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _shoppingDrag(
                              index,
                              'Reorder ${category.name}',
                              !_busy,
                            ),
                            PopupMenuButton<String>(
                              tooltip: '${category.name} options',
                              enabled: !_busy,
                              onSelected: (choice) {
                                if (choice == 'rename') {
                                  _name(id: category.id, name: category.name);
                                }
                                if (choice == 'delete') {
                                  _delete(category.id, category.name);
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Text('Rename'),
                                ),
                                if (category.id != 'other')
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _busy ? null : () => _name(),
                          icon: const Icon(Symbols.add),
                          label: const Text('Add category'),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({required this.store, this.id, required this.name});
  final RecipeStore store;
  final String? id;
  final String name;
  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final _name = TextEditingController(text: widget.name);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a category name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.editShopping(
        widget.id == null
            ? ShoppingEdit.addCategory(name: _name.text.trim())
            : ShoppingEdit.renameCategory(
                id: widget.id!,
                name: _name.text.trim(),
              ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.id == null ? 'Add category' : 'Rename category'),
      scrollable: true,
      content: TextField(
        controller: _name,
        readOnly: _busy,
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _save,
          child: Text(widget.id == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );
}

typedef _ShoppingEntry = ({
  String categoryId,
  String name,
  List<ShoppingItem> items,
  ShoppingItem? item,
});

/// Retains one reorderable list, so its global drop indices still span aisles.
/// Pinning follows actual laid-out rows, without scroll listeners, guessed row
/// heights or rebuilding widgets on each scroll frame.
class _PinnedShoppingCategories extends MultiChildRenderObjectWidget {
  _PinnedShoppingCategories({
    required List<_ShoppingEntry> entries,
    required Widget sliver,
    required List<Widget> bands,
  }) : headingIndices = [
         for (var i = 0; i < entries.length; i++)
           if (entries[i].item == null) i,
       ],
       super(children: [sliver, ...bands]);

  final List<int> headingIndices;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPinnedShoppingCategories(headingIndices);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPinnedShoppingCategories renderObject,
  ) => renderObject.headingIndices = headingIndices;
}

class _RenderPinnedShoppingCategories extends RenderSliver
    with
        ContainerRenderObjectMixin<
          RenderSliver,
          SliverPhysicalContainerParentData
        > {
  _RenderPinnedShoppingCategories(this._headingIndices);
  List<int> _headingIndices;
  RenderSliver? _pinned;
  double _pinnedTop = 0;
  double _pinnedHeight = 0;
  bool _pinnedSemantics = false;

  set headingIndices(List<int> value) {
    _headingIndices = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SliverPhysicalContainerParentData) {
      child.parentData = SliverPhysicalContainerParentData();
    }
  }

  RenderSliverMultiBoxAdaptor? _rows(RenderObject root) {
    if (root is RenderSliverMultiBoxAdaptor) return root;
    RenderSliverMultiBoxAdaptor? result;
    root.visitChildren((child) => result ??= _rows(child));
    return result;
  }

  @override
  void performLayout() {
    final list = firstChild!;
    list.layout(constraints, parentUsesSize: true);
    geometry = list.geometry;
    (list.parentData! as SliverPhysicalParentData).paintOffset = Offset.zero;
    final previous = _pinned;
    final previousSemantics = _pinnedSemantics;
    _pinned = null;
    _pinnedSemantics = false;
    if (geometry!.scrollOffsetCorrection != null) return;

    // Lay out the small set of category bands with the same available width.
    // Render objects reuse their layouts when constraints have not changed.
    final bandConstraints = constraints.copyWith(
      scrollOffset: 0,
      cacheOrigin: 0,
    );
    for (var band = childAfter(list); band != null; band = childAfter(band)) {
      band.layout(bandConstraints, parentUsesSize: true);
    }
    final rows = _rows(list);
    int? visibleIndex;
    double? nextHeadingTop;
    if (rows != null) {
      for (var row = rows.firstChild; row != null; row = rows.childAfter(row)) {
        final data = row.parentData! as SliverMultiBoxAdaptorParentData;
        final top = (data.layoutOffset ?? 0) - constraints.scrollOffset;
        if (top <= 0 || visibleIndex == null) {
          visibleIndex = data.index;
        }
        if (top > 0 && _headingIndices.contains(data.index)) {
          nextHeadingTop = top;
          break;
        }
      }
    }
    if (visibleIndex != null && constraints.scrollOffset > 0) {
      var category = -1;
      for (var i = 0; i < _headingIndices.length; i++) {
        if (_headingIndices[i] <= visibleIndex) category = i;
      }
      if (category >= 0) {
        var band = childAfter(list)!;
        for (var i = 0; i < category; i++) {
          band = childAfter(band)!;
        }
        _pinnedHeight = band.geometry!.scrollExtent;
        _pinnedTop = math.min(
          0,
          math.min(
                nextHeadingTop ?? double.infinity,
                geometry!.scrollExtent - constraints.scrollOffset,
              ) -
              _pinnedHeight,
        );
        if (_pinnedTop + _pinnedHeight > 0) {
          _pinned = band;
          _pinnedSemantics = true;
          // A partially visible original heading already supplies this label.
          // Do not announce the same category twice during its handoff.
          if (rows != null) {
            for (
              var row = rows.firstChild;
              row != null;
              row = rows.childAfter(row)
            ) {
              final data = row.parentData! as SliverMultiBoxAdaptorParentData;
              if (data.index == _headingIndices[category]) {
                _pinnedSemantics =
                    (data.layoutOffset ?? 0) -
                        constraints.scrollOffset +
                        _pinnedHeight <=
                    0;
                break;
              }
            }
          }
          (band.parentData! as SliverPhysicalParentData).paintOffset = Offset(
            0,
            _pinnedTop,
          );
        }
      }
    }
    if (previous != _pinned || previousSemantics != _pinnedSemantics) {
      markNeedsSemanticsUpdate();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!geometry!.visible) return;
    context.paintChild(firstChild!, offset);
    if (_pinned != null) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Rect.fromLTWH(0, 0, constraints.crossAxisExtent, geometry!.paintExtent),
        (context, offset) =>
            context.paintChild(_pinned!, offset + Offset(0, _pinnedTop)),
      );
    }
  }

  @override
  bool hitTestChildren(
    SliverHitTestResult result, {
    required double mainAxisPosition,
    required double crossAxisPosition,
  }) {
    // The band is a label, not a route to the obscured item's checkbox.
    if (_pinned != null && mainAxisPosition < _pinnedTop + _pinnedHeight) {
      return true;
    }
    return firstChild!.hitTest(
      result,
      mainAxisPosition: mainAxisPosition,
      crossAxisPosition: crossAxisPosition,
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(firstChild!);
    if (_pinned != null && _pinnedSemantics) visitor(_pinned!);
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    (child.parentData! as SliverPhysicalParentData).applyPaintTransform(
      transform,
    );
  }

  @override
  double childMainAxisPosition(RenderSliver child) =>
      (child.parentData! as SliverPhysicalParentData).paintOffset.dy;

  @override
  double childCrossAxisPosition(RenderSliver child) => 0;

  @override
  double? childScrollOffset(RenderObject child) => 0;
}

class _ShoppingMove {
  _ShoppingMove(this.checked, this.animation);
  final bool checked;
  final AnimationController animation;
  Timer? timer;
  void dispose() {
    timer?.cancel();
    animation.dispose();
  }
}

class _EditShoppingDialog extends StatefulWidget {
  const _EditShoppingDialog({required this.store, required this.item});
  final RecipeStore store;
  final ShoppingItem item;
  @override
  State<_EditShoppingDialog> createState() => _EditShoppingDialogState();
}

class _EditShoppingDialogState extends State<_EditShoppingDialog> {
  late final _text = TextEditingController(
    text: [
      widget.item.quantityText,
      widget.item.name,
    ].where((s) => s.isNotEmpty).join(' '),
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Enter an item.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final undo = await widget.store.editShopping(
        ShoppingEdit.edit(id: widget.item.id, text: _text.text),
      );
      if (mounted) Navigator.pop(context, undo);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Edit item'),
      content: PixelScrollScope(
        axis: Axis.horizontal,
        builder: (context) => TextField(
          scrollController: PrimaryScrollController.of(context),
          controller: _text,
          textCapitalization: TextCapitalization.none,
          autofocus: true,
          readOnly: _busy,
          decoration: InputDecoration(labelText: 'Item', errorText: _error),
          minLines: 1,
          maxLines: null,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    ),
  );
}

Future<void> showShoppingSelection(
  BuildContext context,
  RecipeStore store,
  Recipe recipe, {
  int scale = 2,
}) async {
  final undo = await showDialog<ShoppingUndo>(
    context: context,
    builder: (_) =>
        _ShoppingSelection(store: store, recipe: recipe, scale: scale),
  );
  if (undo != null && context.mounted) {
    showFeedback(context, 'Added to shopping list');
  }
}

class _ShoppingSelection extends StatefulWidget {
  const _ShoppingSelection({
    required this.store,
    required this.recipe,
    required this.scale,
  });
  final int scale;
  final RecipeStore store;
  final Recipe recipe;
  @override
  State<_ShoppingSelection> createState() => _ShoppingSelectionState();
}

class _ShoppingSelectionState extends State<_ShoppingSelection> {
  late final _selected = {
    for (var i = 0; i < widget.recipe.fields.ingredients.length; i++) i,
  };
  List<String>? _amounts;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _loadAmounts();
  }

  Future<void> _loadAmounts() async {
    try {
      final amounts = widget.scale == 2
          ? await widget.store.repository.ingredientAmounts(
              widget.recipe.fields.ingredients,
            )
          : (await (widget.store.repository as ScalingRepository).scaleRecipe(
              widget.recipe.fields,
              widget.scale,
            )).quantities;
      if (mounted) setState(() => _amounts = amounts);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load ingredient quantities.');
      }
    }
  }

  Future<void> _add() async {
    if (_busy || _selected.isEmpty || _amounts == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final indices = _selected.toList()..sort();
      final undo = await widget.store.addShopping(
        widget.recipe.id,
        indices,
        scale: widget.scale,
      );
      if (mounted) Navigator.pop(context, undo);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ingredients = widget.recipe.fields.ingredients;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('Add to shopping list'),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(
                            () => _selected.addAll(
                              List.generate(ingredients.length, (i) => i),
                            ),
                          ),
                    child: const Text('Select all'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(_selected.clear),
                    child: const Text('Select none'),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_amounts == null && _error == null)
                const LinearProgressIndicator(),
              Flexible(
                child: PixelSingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < ingredients.length; i++) ...[
                        if (ingredients[i].section.isNotEmpty &&
                            (i == 0 ||
                                ingredients[i - 1].section !=
                                    ingredients[i].section))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                ingredients[i].section,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ),
                        CheckboxListTile(
                          value: _selected.contains(i),
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(ingredients[i].name),
                          subtitle: Text(
                            [
                              if (_amounts != null) _amounts![i],
                              if (widget.scale == 2)
                                displayIngredientUnit(ingredients[i]),
                              ingredients[i].prepNote,
                              if (ingredients[i].optional) '(optional)',
                            ].where((s) => s.isNotEmpty).join(' '),
                          ),
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                  value == true
                                      ? _selected.add(i)
                                      : _selected.remove(i);
                                }),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _busy || _selected.isEmpty || _amounts == null
                ? null
                : _add,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
