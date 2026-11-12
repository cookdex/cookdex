import 'page_headings.dart';
import 'pixel_scroll.dart';

import 'dart:async';

import '../fraction_display.dart';

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
import 'facelift_motion.dart';
import 'facelift_tokens.dart';
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
    this.controller,
  });
  final RecipeStore store;
  final ScrollController? controller;
  final Future<void> Function(BuildContext context) onSaveText;

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen>
    with TickerProviderStateMixin {
  final _draggedRow = ValueNotifier<String?>(null);
  bool _landingDrop = false;
  bool _checkedExpanded = false;
  // ReorderableList translates neighboring rows for 250ms after the gap moves.
  // Repaint only the card backing while those paint transforms are changing.
  late final _gapMotion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  late final _departure = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) _finishMoves();
    });
  Duration _checkPause = Duration.zero;
  Timer? _batchTimer;
  Timer? _arrivalTimer;
  Duration _moveDuration = Duration.zero;
  Timer? _allDone;
  int _previousUnchecked = 0;
  int? _dragGeneration;
  ({List<ShoppingItem> snapshot, String id, String category, String? before})?
  _pendingDrop;
  final _input = TextEditingController();
  int _inputRevision = 0;
  int? _submittedRevision;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _busy = false;
  String? _inputError;
  bool _reduceMotion = false;
  final _placements = <String, bool>{};
  final _checkWrites = <String, bool>{};
  final _queued = <String, bool>{};
  final _departing = <String, bool>{};
  final _arrivals = <String>{};
  bool get _editingLocked => _busy || _checkWrites.isNotEmpty;
  bool get _movingRows => _queued.isNotEmpty || _departing.isNotEmpty;
  bool _moving(String id) =>
      _queued.containsKey(id) || _departing.containsKey(id);

  @override
  void initState() {
    super.initState();
    _previousUnchecked = widget.store.uncheckedShoppingCount;
    _resetPlacements();
    widget.store.addListener(_shoppingChanged);
  }

  @override
  void didUpdateWidget(ShoppingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _submittedRevision = null;
      _inputRevision++;
      oldWidget.store.removeListener(_shoppingChanged);
      if (_dragGeneration != null) _dragGeneration = -1;
      _draggedRow.value = null;
      _pendingDrop = null;
      _checkWrites.clear();
      _allDone?.cancel();
      _allDone = null;
      _previousUnchecked = widget.store.uncheckedShoppingCount;
      _resetPlacements();
      widget.store.addListener(_shoppingChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPause = FaceliftMotion.checkOffDelay(context);
    // Share one 250ms transition between collapse and expansion at normal speed.
    _moveDuration = FaceliftMotion.duration(
      context,
      MotionGroup.lists,
      fraction: 125 / 220,
    );
    _departure.duration = _moveDuration;
    _reduceMotion = _moveDuration == Duration.zero;
    if (_reduceMotion) _resetPlacements();
  }

  void _resetPlacements() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _arrivalTimer?.cancel();
    _departure.stop();
    _queued.clear();
    _departing.clear();
    _arrivals.clear();
    _placements
      ..clear()
      ..addEntries(
        widget.store.shopping.map(
          (i) => MapEntry(i.id, _checkWrites[i.id] ?? i.checked),
        ),
      );
  }

  void _updateCompletion() {
    final remaining = widget.store.shopping
        .where((item) => !(_checkWrites[item.id] ?? item.checked))
        .length;
    final finished =
        remaining == 0 &&
        _previousUnchecked > 0 &&
        widget.store.shopping.any(
          (item) =>
              (_checkWrites[item.id] ?? item.checked) &&
              (_checkWrites[item.id] == true || _placements[item.id] == false),
        );
    _previousUnchecked = remaining;
    if (remaining > 0 || widget.store.shopping.isEmpty) {
      _allDone?.cancel();
      _allDone = null;
    } else if (finished) {
      _allDone?.cancel();
      _allDone = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _allDone = null);
      });
    }
  }

  void _shoppingChanged() {
    if (!mounted) return;
    if (!TickerMode.valuesOf(context).enabled ||
        ModalRoute.isCurrentOf(context) == false) {
      _previousUnchecked = widget.store.uncheckedShoppingCount;
      _allDone?.cancel();
      _allDone = null;
      _resetPlacements();
      return;
    }
    setState(() {
      _updateCompletion();
      final items = widget.store.shopping;
      if (_reduceMotion) {
        _resetPlacements();
        return;
      }
      final ids = items.map((i) => i.id).toSet();
      _placements.removeWhere((id, _) => !ids.contains(id));
      _queued.removeWhere((id, _) => !ids.contains(id));
      _departing.removeWhere((id, _) => !ids.contains(id));
      var externalCheck = false;
      for (final item in items) {
        final placement = _placements.putIfAbsent(item.id, () => item.checked);
        final target = _checkWrites[item.id] ?? item.checked;
        if (placement == target) {
          _queued.remove(item.id);
          _departing.remove(item.id);
        } else if (!_departing.containsKey(item.id) &&
            !_queued.containsKey(item.id)) {
          _queued[item.id] = target;
          if (!_checkWrites.containsKey(item.id)) externalCheck = true;
        }
      }
      if (_departing.isEmpty) _departure.stop();
      if (externalCheck) _holdChecks();
      _startReadyMoves();
    });
  }

  void _holdChecks() {
    if (_reduceMotion) return;
    _batchTimer?.cancel();
    _batchTimer = Timer(_checkPause, () {
      _batchTimer = null;
      if (mounted) setState(_startReadyMoves);
    });
  }

  void _startReadyMoves() {
    if (_batchTimer != null || _departing.isNotEmpty || _queued.isEmpty) {
      return;
    }
    // A closed Checked group has no visible arrival to animate.
    _departure.duration =
        !_checkedExpanded && _queued.values.every((target) => target)
        ? _moveDuration * 2
        : _moveDuration;
    _departing.addAll(_queued);
    _queued.clear();
    _departure.forward(from: 0);
  }

  void _finishMoves() {
    if (!mounted || _departing.isEmpty) return;
    setState(() {
      _placements.addAll(_departing);
      _arrivals
        ..clear()
        ..addAll(_departing.keys);
      _departing.clear();
      _arrivalTimer?.cancel();
      _arrivalTimer = Timer(_moveDuration, _arrivals.clear);
      _startReadyMoves();
    });
  }

  Future<void> _checkRow(ShoppingItem item) async {
    if (_busy || _checkWrites.containsKey(item.id) || _moving(item.id)) return;
    HapticFeedback.selectionClick();
    final store = widget.store;
    final checked = !item.checked;
    setState(() {
      _checkWrites[item.id] = checked;
      _updateCompletion();
      if (_reduceMotion) {
        _placements[item.id] = checked;
      } else {
        _queued[item.id] = checked;
        _holdChecks();
      }
    });
    try {
      // Persistence runs independently of the gesture and its animation.
      await store.checkShoppingRow(item.id, checked);
    } catch (error) {
      if (mounted && identical(store, widget.store)) {
        showFeedbackWithMessenger(
          _messenger.currentState!,
          _message(error),
          kind: FeedbackKind.error,
        );
      }
    } finally {
      if (mounted && identical(store, widget.store)) {
        setState(() {
          _checkWrites.remove(item.id);
          final current = store.shopping
              .where((row) => row.id == item.id)
              .firstOrNull;
          if (current != null && current.checked != checked) {
            _updateCompletion();
            _queued.remove(item.id);
            _departing.remove(item.id);
            _arrivals.remove(item.id);
            _placements[item.id] = current.checked;
            if (_departing.isEmpty) _departure.stop();
          }
          _startReadyMoves();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_shoppingChanged);
    _batchTimer?.cancel();
    _arrivalTimer?.cancel();
    _departure.dispose();
    _gapMotion.dispose();
    _draggedRow.dispose();
    _allDone?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<bool> _change(ShoppingEdit edit, [String? undoMessage]) async {
    if (_editingLocked) return false;
    setState(() => _busy = true);
    try {
      return await _saveEdit(edit, undoMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _saveEdit(ShoppingEdit edit, [String? undoMessage]) async {
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
    }
  }

  Future<void> _add() async {
    final revision = _inputRevision;
    if (_submittedRevision == revision) return;
    final text = _input.text;
    if (text.trim().isEmpty) {
      setState(() => _inputError = 'Enter an item.');
      return;
    }
    _submittedRevision = revision;
    final saved = await _saveEdit(ShoppingEdit.addManual(text: text));
    if (mounted && _submittedRevision == revision) {
      _submittedRevision = null;
      if (saved && _inputRevision == revision && _input.text == text) {
        _input.clear();
      }
    }
  }

  Future<void> _edit(ShoppingItem item) async {
    if (_editingLocked) return;
    await showDialog<ShoppingUndo>(
      context: context,
      builder: (_) => _EditShoppingDialog(store: widget.store, item: item),
    );
  }

  Future<void> _itemMenu(ShoppingItem item) async {
    if (_editingLocked || _moving(item.id)) return;
    final choice = await showCookdexSheet<String>(
      context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final source = widget.store.shoppingSourceLabel(item);
          final delete = mutedDeleteColor(theme.colorScheme);
          final category = widget.store.shoppingCategories
              .where((category) => category.id == item.categoryId)
              .firstOrNull;
          final detail = [
            if (category != null) 'In ${category.name}',
            if (source != null) 'from $source',
          ].join(' · ');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [
                  if (item.quantityText.isNotEmpty)
                    displayFractions(item.quantityText),
                  item.name,
                ].join(' '),
                style: FaceliftTokens.sheetTitle(context),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FaceliftQuickGrid(
                longestLabel: 'Move to category',
                children: [
                  FaceliftQuickAction(
                    label: 'Edit',
                    icon: const Icon(Symbols.edit),
                    onTap: () => Navigator.pop(context, 'edit'),
                  ),
                  FaceliftQuickAction(
                    label: 'Move to category',
                    icon: const Icon(Symbols.drive_file_move),
                    onTap: () => Navigator.pop(context, 'move'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Material(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Symbols.delete, color: delete),
                        const SizedBox(width: 10),
                        Text(
                          'Delete',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: delete,
                          ),
                        ),
                      ],
                    ),
                  ),
                  onTap: () => Navigator.pop(context, 'delete'),
                ),
              ),
            ],
          );
        },
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
  ) {
    final departing =
        _departing.isNotEmpty &&
        items.every((item) => _departing[item.id] == true);
    return TweenAnimationBuilder<double>(
      key: ValueKey('shopping-heading-$categoryId'),
      tween: Tween(
        begin:
            _arrivals.isNotEmpty &&
                items.every((item) => _arrivals.contains(item.id))
            ? 0
            : 1,
        end: 1,
      ),
      duration: _moveDuration,
      builder: (context, arrival, child) => AnimatedBuilder(
        animation: departing ? _departure : const AlwaysStoppedAnimation(0.0),
        builder: (context, child) {
          final departure = departing
              ? Curves.easeInOutCubic.transform(_departure.value)
              : 0.0;
          final value = arrival * (1 - departure);
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
      child: _categoryBand(categoryId, name, items),
    );
  }

  Widget _categoryBand(String id, String name, List<ShoppingItem> items) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final count = items
        .where((item) => !(_checkWrites[item.id] ?? item.checked))
        .length;
    final icon = switch (id) {
      'produce' => Symbols.nutrition,
      'meat' => Symbols.set_meal,
      'dairy' => Symbols.egg,
      'bakery' => Symbols.bakery_dining,
      'pantry' => Symbols.shelves,
      'canned' => Symbols.grocery,
      'spices' => Symbols.stockpot,
      'frozen' => Symbols.ac_unit,
      'beverages' => Symbols.local_drink,
      'household' => Symbols.cleaning_services,
      _ => Symbols.shopping_basket,
    };
    return ColoredBox(
      color: colors.surface,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.fromLTRB(12, 10, 16, 6),
        decoration: BoxDecoration(
          color: colors.surfaceContainer,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FaceliftTokens.groupRadius),
          ),
        ),
        child: Semantics(
          header: true,
          label: '$name, $count unchecked',
          excludeSemantics: true,
          child: Row(
            children: [
              Container(
                width: FaceliftTokens.categoryIconSize,
                height: FaceliftTokens.categoryIconSize,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(
                    FaceliftTokens.categoryIconRadius,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name, style: FaceliftTokens.categoryTitle(context)),
              ),
              const SizedBox(width: 8),
              Text(
                '$count',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
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
    // The framework reports indices after its drop animation. A sync or
    // other write during the gesture may have put different items there.
    final generation = _dragGeneration;
    _dragGeneration = null;
    if (generation != null && generation != widget.store.generation) return;
    if (_editingLocked || _movingRows || oldIndex == newIndex) return;
    final item = entries[oldIndex].item;
    if (item == null) return;
    final reordered = entries.toList();
    reordered.insert(newIndex, reordered.removeAt(oldIndex));
    // A drop before the first heading means the first item in that category.
    var destination = entries.first.categoryId;
    for (var i = 0; i < newIndex; i++) {
      if (reordered[i].item == null) destination = reordered[i].categoryId;
    }
    String? beforeId;
    for (final entry in reordered.skip(newIndex + 1)) {
      if (entry.item != null && entry.categoryId == destination) {
        beforeId = entry.item!.id;
        break;
      }
    }
    final ShoppingEdit edit;
    if (destination == item.categoryId) {
      final ids = [
        for (final entry in reordered)
          if (entry.item != null && entry.categoryId == destination)
            entry.item!.id,
      ];
      edit = ShoppingEdit.reorderItems(categoryId: destination, ids: ids);
    } else {
      edit = ShoppingEdit.move(
        id: item.id,
        categoryId: destination,
        beforeId: beforeId,
      );
    }
    // Preview just the dropped row. A new store snapshot takes precedence,
    // including remote changes or a generation refresh after a failed save.
    final drop = (
      snapshot: widget.store.shopping,
      id: item.id,
      category: destination,
      before: beforeId,
    );
    setState(() => _pendingDrop = drop);
    _change(edit).whenComplete(() {
      if (mounted && _pendingDrop == drop) setState(() => _pendingDrop = null);
    });
  }

  Future<void> _menu(String choice) async {
    if (_editingLocked) return;
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

  Widget _row(ShoppingItem item, {int? dragIndex}) {
    final source = widget.store.shoppingSourceLabel(item);
    final theme = Theme.of(context);
    final checked = _checkWrites[item.id] ?? item.checked;
    final decoration = checked ? TextDecoration.lineThrough : null;
    final enabled =
        !_busy && !_checkWrites.containsKey(item.id) && !_moving(item.id);
    return GestureDetector(
      key: ValueKey(item.id),
      onSecondaryTap: enabled && !_editingLocked ? () => _itemMenu(item) : null,
      child: MergeSemantics(
        child: Semantics(
          checked: checked,
          enabled: enabled,
          child: ListTile(
            contentPadding: const EdgeInsets.only(left: 14, right: 4),
            minTileHeight: source == null ? 48 : 56,
            minVerticalPadding: 4,
            minLeadingWidth: 24,
            horizontalTitleGap: 12,
            titleAlignment: ListTileTitleAlignment.center,
            trailing: dragIndex == null
                ? null
                : _shoppingDrag(
                    dragIndex,
                    'Reorder ${item.name}',
                    enabled && !_editingLocked && !_movingRows,
                  ),
            leading: ExcludeSemantics(
              child: Icon(
                checked ? Symbols.check_circle : Symbols.radio_button_unchecked,
                fill: checked ? 1 : 0,
                color: checked
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            title: Text.rich(
              key: ValueKey('shopping-item-label-${item.id}'),
              TextSpan(
                children: [
                  if (item.quantityText.isNotEmpty)
                    TextSpan(
                      text: '${displayFractions(item.quantityText)} ',
                      semanticsLabel: '${spokenFractions(item.quantityText)} ',
                      style: amountDisplayStyle,
                    ),
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
            onTap: enabled ? () => _checkRow(item) : null,
            onLongPress: enabled && !_editingLocked
                ? () => _itemMenu(item)
                : null,
          ),
        ),
      ),
    );
  }

  Widget _animatedRow(
    ShoppingItem item, {
    int? dragIndex,
    bool last = false,
    String? lastRowAfterDivider,
  }) => TweenAnimationBuilder<double>(
    key: ValueKey('shopping-row-${item.id}-${_placements[item.id]}'),
    tween: Tween(begin: _arrivals.contains(item.id) ? 0 : 1, end: 1),
    duration: _reduceMotion ? Duration.zero : _moveDuration,
    curve: Curves.easeInOutCubic,
    builder: (context, arrival, child) => AnimatedBuilder(
      animation: _departing.containsKey(item.id)
          ? _departure
          : const AlwaysStoppedAnimation(0.0),
      builder: (context, child) {
        final departure = _departing.containsKey(item.id)
            ? _departure.value
            : 0.0;
        final value =
            arrival * (1 - Curves.easeInOutCubic.transform(departure));
        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: value,
            child: Transform.translate(
              offset: Offset(
                0,
                (_departing[item.id] == true ? 14 : -14) * departure,
              ),
              child: Opacity(opacity: value, child: child),
            ),
          ),
        );
      },
      child: child,
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: dragIndex == null ? 0 : 16),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: last
            ? const BorderRadius.vertical(
                bottom: Radius.circular(FaceliftTokens.groupRadius),
              )
            : null,
        clipBehavior: last ? Clip.antiAlias : Clip.none,
        child: Column(
          children: [
            _row(item, dragIndex: dragIndex),
            if (lastRowAfterDivider != null)
              ValueListenableBuilder<String?>(
                valueListenable: _draggedRow,
                child: const Divider(indent: 50, endIndent: 16),
                builder: (context, lifted, child) => Opacity(
                  opacity: lifted == lastRowAfterDivider ? 0 : 1,
                  child: child,
                ),
              )
            else if (!last)
              const Divider(indent: 50, endIndent: 16),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final items = widget.store.shopping;
    final checked = <ShoppingItem>[];
    final unchecked = <ShoppingItem>[];
    final remaining = widget.store.uncheckedShoppingCount;
    for (final item in items) {
      (_placements[item.id] == true ? checked : unchecked).add(item);
    }
    final pending = _pendingDrop;
    final drop = pending != null && identical(items, pending.snapshot)
        ? pending
        : null;
    final groups = <String, List<ShoppingItem>>{};
    for (final item in unchecked) {
      final group = item.id == drop?.id ? drop!.category : item.categoryId;
      (groups[group] ??= []).add(item);
    }
    if (drop != null) {
      final rows = groups[drop.category]!;
      final moved = rows.removeAt(
        rows.indexWhere((item) => item.id == drop.id),
      );
      final index = rows.indexWhere((item) => item.id == drop.before);
      rows.insert(index < 0 ? rows.length : index, moved);
    }
    final entries = <_ShoppingEntry>[];
    for (final category in widget.store.shoppingCategories) {
      final rows = groups[category.id];
      if (rows == null || rows.isEmpty) continue;
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

    // ReorderableList requests the same visible children on pointer moves.
    // Reuse their widget instances until the page rebuilds with new state.
    // The bound also covers long drags that auto-scroll through many aisles.
    final rows = <int, Widget>{};
    Widget buildRow(BuildContext context, int index) {
      final cached = rows[index];
      if (cached != null) return cached;
      if (rows.length >= 32) rows.remove(rows.keys.first);
      final entry = entries[index];
      final item = entry.item;
      if (item == null) {
        return rows[index] = _categoryHeading(
          entry.categoryId,
          entry.name,
          entry.items,
        );
      }
      final group = entry.items;
      return rows[index] = _animatedRow(
        item,
        dragIndex: index,
        last: group.last.id == item.id,
        lastRowAfterDivider:
            group.length > 1 && group[group.length - 2].id == item.id
            ? group.last.id
            : null,
      );
    }

    return ScaffoldMessenger(
      key: _messenger,
      child: Scaffold(
        key: _scaffold,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              TabHeading(
                title: const Text('Shopping list'),
                subtitle: Text(
                  '$remaining ${remaining == 1 ? 'item' : 'items'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                action: PopupMenuButton<String>(
                  icon: const Icon(Symbols.more_vert),
                  tooltip: 'Shopping list options',
                  enabled: !_editingLocked,
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
                          color: mutedDeleteColor(
                            Theme.of(context).colorScheme,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Listener(
                  onPointerMove: (_) {
                    if (_draggedRow.value != null && !_landingDrop) {
                      _gapMotion.forward(from: 0);
                    }
                  },
                  onPointerCancel: (_) {
                    _draggedRow.value = null;
                  },
                  child: PixelCustomScrollView(
                    controller: widget.controller,
                    slivers: [
                      if (items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const FaceliftIconTile(
                                    Symbols.shopping_basket,
                                    size: 56,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Add your first shopping item.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (entries.isNotEmpty)
                        _PinnedShoppingCategories(
                          entries: entries,
                          gapMotion: _gapMotion,
                          liftedRow: _draggedRow,
                          dragColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainer,
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
                            onReorderStart: (index) {
                              _dragGeneration = widget.store.generation;
                              _landingDrop = false;
                              _gapMotion.stop();
                              _draggedRow.value = entries[index].item?.id;
                              HapticFeedback.lightImpact();
                            },
                            onReorderEnd: (_) {
                              // The proxy keeps landing after the finger lifts.
                              _landingDrop = true;
                              _gapMotion.forward(from: 0).then((_) {
                                if (mounted) _draggedRow.value = null;
                              });
                            },
                            proxyDecorator: (child, index, animation) {
                              final item = entries[index].item!;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Material(
                                  key: const ValueKey('shopping-drag-proxy'),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                                  elevation: 3,
                                  borderRadius: BorderRadius.circular(
                                    FaceliftTokens.groupRadius,
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: _row(item, dragIndex: index),
                                ),
                              );
                            },
                            itemBuilder: buildRow,
                            onReorderItem: (oldIndex, newIndex) =>
                                _reorderShopping(entries, oldIndex, newIndex),
                          ),
                        ),
                      if (_allDone != null &&
                          entries.isEmpty &&
                          checked.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              borderRadius: BorderRadius.circular(
                                FaceliftTokens.groupRadius,
                              ),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    'All done',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                        ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _editingLocked
                                      ? null
                                      : () => _menu('checked'),
                                  child: const Text('Clear checked'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (checked.isNotEmpty)
                        SliverToBoxAdapter(
                          key: const ValueKey('checked-shopping-group'),
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainer,
                              borderRadius: BorderRadius.circular(
                                FaceliftTokens.groupRadius,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ExpansionTile(
                              key: const PageStorageKey(
                                'checked-shopping-items',
                              ),
                              onExpansionChanged: (expanded) =>
                                  _checkedExpanded = expanded,
                              title: Text('Checked (${checked.length})'),
                              leading: Icon(
                                Symbols.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              shape: const Border(),
                              collapsedShape: const Border(),
                              initiallyExpanded: _checkedExpanded,
                              expansionAnimationStyle: AnimationStyle(
                                duration: _moveDuration,
                                reverseDuration: _moveDuration,
                                curve: Curves.easeInOutCubic,
                              ),
                              children: [
                                for (final item in checked)
                                  _animatedRow(
                                    item,
                                    last: item.id == checked.last.id,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
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
              16,
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
                      decoration: InputDecoration(
                        hintText: 'Add an item',
                        errorText: _inputError,
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        _inputRevision++;
                        if (_inputError != null) {
                          setState(() => _inputError = null);
                        }
                      },
                      onSubmitted: (_) => _add(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Add item',
                  onPressed: _add,
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
        appBar: pageHeadingBar(context, title: 'Categories'),
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
      content: DialogFieldPadding(
        child: TextField(
          controller: _name,
          readOnly: _busy,
          decoration: InputDecoration(labelText: 'Name', errorText: _error),
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
        ),
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
    required this.gapMotion,
    required this.liftedRow,
    required this.dragColor,
    required List<_ShoppingEntry> entries,
    required Widget sliver,
    required List<Widget> bands,
  }) : headingIndices = [
         for (var i = 0; i < entries.length; i++)
           if (entries[i].item == null) i,
       ],
       super(children: [sliver, ...bands]);

  final List<int> headingIndices;
  final Listenable gapMotion;
  final ValueNotifier<String?> liftedRow;
  final Color dragColor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPinnedShoppingCategories(
        headingIndices,
        gapMotion,
        liftedRow,
        dragColor,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPinnedShoppingCategories renderObject,
  ) {
    renderObject.headingIndices = headingIndices;
    renderObject.dragColor = dragColor;
  }
}

class _RenderPinnedShoppingCategories extends RenderSliver
    with
        ContainerRenderObjectMixin<
          RenderSliver,
          SliverPhysicalContainerParentData
        > {
  _RenderPinnedShoppingCategories(
    this._headingIndices,
    this.gapMotion,
    this.liftedRow,
    this.dragColor,
  );
  final Listenable gapMotion;
  final ValueNotifier<String?> liftedRow;
  Color dragColor;
  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    gapMotion.addListener(markNeedsPaint);
    liftedRow.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    gapMotion.removeListener(markNeedsPaint);
    liftedRow.removeListener(markNeedsPaint);
    super.detach();
  }

  List<int> _headingIndices;
  RenderSliver? _pinned;
  double _pinnedTop = 0;
  double _pinnedHeight = 0;
  double _categoryBottom = 0;
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
        _categoryBottom = math.min(
          nextHeadingTop ?? double.infinity,
          geometry!.scrollExtent - constraints.scrollOffset,
        );
        _pinnedTop = math.min(0, _categoryBottom - _pinnedHeight);
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
    if (_pinned == null ||
        _categoryBottom >= _pinnedHeight + FaceliftTokens.groupRadius) {
      _paintListAndBand(context, offset);
      return;
    }
    // Only during push-off: clip the outgoing band and the rows under it
    // together so its backing cannot square off the final item's corners.
    final bounds = Rect.fromLTWH(
      0,
      0,
      constraints.crossAxisExtent,
      geometry!.paintExtent,
    );
    final bottom = math.min(_categoryBottom, bounds.height);
    final card = Rect.fromLTRB(16, 0, bounds.width - 16, bottom);
    final clip = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          card,
          const Radius.circular(FaceliftTokens.groupRadius),
        ).scaleRadii(),
      )
      ..addRect(Rect.fromLTRB(0, bottom, bounds.width, bounds.height));
    context.pushClipPath(
      needsCompositing,
      offset,
      bounds,
      clip,
      _paintListAndBand,
    );
  }

  void _paintListAndBand(PaintingContext context, Offset offset) {
    if (liftedRow.value == null) {
      context.paintChild(firstChild!, offset);
    } else {
      _paintDragCards(context, offset, dragColor);
    }
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

  // The framework translates items to open a drop gap. Use the painted
  // heading positions to give the entire gap the destination card surface
  // and round the newly exposed edge of the source card.
  void _paintDragCards(PaintingContext context, Offset offset, Color color) {
    final rows = _rows(firstChild!);
    final bounds = Rect.fromLTWH(
      0,
      0,
      constraints.crossAxisExtent,
      geometry!.paintExtent,
    );
    final cards = Path();
    var start = -constraints.scrollOffset;
    void addCard(double end) {
      if (end <= start || end <= 0 || start >= bounds.bottom) return;
      cards.addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(16, start, bounds.width - 16, end),
          const Radius.circular(FaceliftTokens.groupRadius),
        ).scaleRadii(),
      );
    }

    if (rows != null) {
      for (var row = rows.firstChild; row != null; row = rows.childAfter(row)) {
        final data = row.parentData! as SliverMultiBoxAdaptorParentData;
        if (!_headingIndices.contains(data.index)) continue;
        // Only the first Transform above the heading belongs to reorder.
        RenderObject heading = row;
        while (heading is! RenderTransform) {
          RenderObject? next;
          heading.visitChildren((child) => next ??= child);
          if (next == null) break;
          heading = next!;
        }
        final transform = Matrix4.identity();
        if (heading is RenderTransform && heading.child != null) {
          heading.applyPaintTransform(heading.child!, transform);
        }
        final shift = transform.getTranslation().y;
        final top = (data.layoutOffset ?? 0) - constraints.scrollOffset + shift;
        addCard(top);
        start = top + 8;
      }
    }
    addCard(geometry!.scrollExtent - constraints.scrollOffset);
    context.pushClipPath(needsCompositing, offset, bounds, cards, (
      context,
      offset,
    ) {
      context.canvas.drawRect(bounds.shift(offset), Paint()..color = color);
      context.paintChild(firstChild!, offset);
    });
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
        builder: (context) => DialogFieldPadding(
          child: TextField(
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
                          subtitle: Text.rich(
                            TextSpan(
                              children: [
                                if (_amounts != null)
                                  TextSpan(
                                    text: displayFractions(_amounts![i]),
                                    semanticsLabel: spokenFractions(
                                      _amounts![i],
                                    ),
                                    style: amountDisplayStyle,
                                  ),
                                TextSpan(
                                  text:
                                      [
                                            if (widget.scale == 2)
                                              displayIngredientUnit(
                                                ingredients[i],
                                              ),
                                            ingredients[i].prepNote,
                                            if (ingredients[i].optional)
                                              '(optional)',
                                          ]
                                          .where((s) => s.isNotEmpty)
                                          .map((s) => ' $s')
                                          .join(),
                                ),
                              ],
                            ),
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
