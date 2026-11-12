import 'pixel_scroll.dart';
import 'idle_build_ahead.dart';
import 'window_size.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../editor_controller.dart';
import '../editor_model.dart';
import '../name_matching.dart';
import '../recipe_store.dart';
import '../tag_labels.dart';
import '../youtube_import.dart' show amountGuessNote;
import '../src/rust/api.dart' as core;
import 'components.dart';
import 'facelift_motion.dart';
import 'feedback.dart';
import 'navigation_feedback.dart';

const standardUnits = [
  'tbsp',
  'tsp',
  'cup',
  'oz',
  'lb',
  'g',
  'kg',
  'ml',
  'l',
  'pinch',
  'clove',
  'can',
];

class RecipeEditor extends StatefulWidget {
  const RecipeEditor({
    super.key,
    required this.controller,
    this.tagSuggestions = const [],
    this.ingredientSuggestions = const [],
    this.onSmartCreateSaved,
  });
  final EditorController controller;
  final List<String> tagSuggestions, ingredientSuggestions;
  final ValueChanged<core.Recipe>? onSmartCreateSaved;
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor>
    with WidgetsBindingObserver {
  EditorController get c => widget.controller;
  EditorDraft get d => c.draft;
  bool _leaving = false, _backDialog = false;
  String? _placingSection;
  _SectionDragSession? _sectionDragSession;
  bool get _sectionDrag => _sectionDragSession != null;
  Duration get _sectionTransition =>
      FaceliftMotion.duration(context, MotionGroup.lists);
  final _editorViewportKey = GlobalKey();
  double _sectionFocusSpace = 0;
  final _scroll = PixelScrollController();
  final _sectionKeys = <String, GlobalKey>{};
  final _ingredientLinks = <String, LayerLink>{};
  final _ingredientsHeadingKey = GlobalKey();
  final _ingredientListKey = GlobalKey<SliverReorderableListState>();
  final _suggestions = _EditorSuggestions();
  final _keyboardVisible = ValueNotifier(false);
  Timer? _keyboardSettleTimer;
  double _keyboardInset = 0;
  List<String> _usedUnits = const [];
  final _hintWidths = <String, double>{};
  static final _word = RegExp(r'\S+');
  Timer? _unitTimer;
  late final List<String> _ingredientNames;
  late final List<String> _tags;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final summaries = c.store.summaries;
    _ingredientNames = summaries.isEmpty
        ? rankEditorSuggestions(widget.ingredientSuggestions)
        : c.store.editorIngredientNames;
    _tags = summaries.isEmpty
        ? rankEditorSuggestions(widget.tagSuggestions)
        : c.store.editorTags;
    _unitTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_loadUnitSuggestions()),
    );
  }

  Future<void> _loadUnitSuggestions() async {
    // Let the route settle before collection suggestions. Yield between details;
    // never flood the bridge/UI with every recipe at once on editor entry.
    if (!mounted) return;
    try {
      final repository = c.store.repository;
      final units = repository is RustRecipeRepository
          ? await repository.session.editorUnits()
          : (await Future.wait(
                  c.store.summaries.map((r) => c.store.detail(r.id)),
                ))
                .whereType<core.Recipe>()
                .expand((r) => r.fields.ingredients.map((i) => i.unit))
                .toList();
      if (!mounted) return;
      _usedUnits = rankEditorSuggestions(units);
      final active = _suggestions.active;
      if (active != null) _suggestions.refresh(active);
    } catch (_) {
      // Standard units remain available if a collection detail cannot load.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Font, scale and direction can all change the actual hint width.
    _hintWidths.clear();
    _updateKeyboardInset();
  }

  @override
  void dispose() {
    _sectionDragSession?.dispose();
    _scroll.dispose();
    _unitTimer?.cancel();
    _keyboardSettleTimer?.cancel();
    unawaited(c.flush());
    WidgetsBinding.instance.removeObserver(this);
    _keyboardVisible.dispose();
    _suggestions.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _updateKeyboardInset();
  }

  void _updateKeyboardInset() {
    final inset = View.of(context).viewInsets.bottom;
    if (inset == _keyboardInset) return;
    _keyboardInset = inset;
    _keyboardSettleTimer?.cancel();
    // The strip does not ride the IME's inset animation. Hide at the first
    // movement and reveal once metrics settle, without rebuilding editor rows.
    _keyboardVisible.value = false;
    if (inset > 0) {
      _keyboardSettleTimer = Timer(const Duration(milliseconds: 80), () {
        if (mounted) _keyboardVisible.value = true;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(c.flush());
  }

  Future<void> _back() async {
    if (_placingSection != null) {
      setState(() => _placingSection = null);
      return;
    }
    if (_sectionDrag) {
      unawaited(_finishSectionDrag(cancel: true));
      return;
    }
    if (c.saving || _backDialog || _leaving) return;
    await c.flush();
    if (!mounted) return;
    _backDialog = true;
    try {
      if (c.dirty &&
          !await confirmCookdex(
            context,
            title: 'Discard changes?',
            action: 'Discard',
            destructive: true,
          )) {
        return;
      }
      await c.discard();
      if (!mounted) return;
      setState(() => _leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Could not discard the local draft.',
          kind: FeedbackKind.error,
        );
      }
    } finally {
      _backDialog = false;
    }
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final saved = await c.save(
      showSaving: () => WidgetsBinding.instance.endOfFrame,
      chooseDuplicate: _chooseDuplicate,
      reviewNames: _reviewNames,
    );
    if (!mounted) return;
    if (saved == null) {
      return;
    }
    if (c.persistenceError != null) {
      showFeedback(context, c.persistenceError!, kind: FeedbackKind.error);
    }
    setState(() => _leaving = true);
    if (widget.onSmartCreateSaved case final action?) {
      action(saved);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  Future<Set<int>?> _reviewNames(List<NameMatch> matches) {
    if (!mounted) return Future.value(null);
    return showDialog<Set<int>>(
      context: context,
      builder: (_) => NameMatchReview(matches: matches),
    );
  }

  Future<core.DuplicateChoice?> _chooseDuplicate(
    List<core.RecipeSummary> duplicates,
  ) async {
    if (!mounted) return null;
    var selected = duplicates.length == 1 ? duplicates.single : null;
    return showDialog<core.DuplicateChoice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Recipe already exists'),
          content: duplicates.length == 1
              ? Text(duplicates.single.title)
              : SizedBox(
                  width: 400,
                  child: PixelSingleChildScrollView(
                    child: RadioGroup<core.RecipeSummary>(
                      groupValue: selected,
                      onChanged: (value) => update(() => selected = value),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (index, recipe) in duplicates.indexed)
                            RadioListTile<core.RecipeSummary>(
                              key: ValueKey('duplicate-${recipe.id}'),
                              value: recipe,
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Recipe ${index + 1}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                  Text(recipe.title),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _duplicateUpdated(
                                      context,
                                      recipe.updatedAt,
                                    ),
                                  ),
                                  if (recipe.description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(recipe.description),
                                    ),
                                  if (recipe.ingredients.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Ingredients: ${recipe.ingredients.join(', ')}',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, const core.DuplicateChoice.keepBoth()),
              child: const Text('Keep both'),
            ),
            TextButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(
                      context,
                      core.DuplicateChoice.replace(id: selected!.id),
                    ),
              child: const Text('Replace'),
            ),
          ],
        ),
      ),
    );
  }

  String _duplicateUpdated(BuildContext context, String value) {
    final at = DateTime.tryParse(value)?.toLocal();
    if (at == null) return 'Update time unavailable';
    final date = MaterialLocalizations.of(context).formatShortDate(at);
    if (!value.contains('T') && !value.contains(' ')) return 'Updated $date';
    String two(int part) => part.toString().padLeft(2, '0');
    return 'Updated $date · ${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  void _edit(VoidCallback action) {
    action();
    c.changed(structural: false);
  }

  void _change(VoidCallback action) {
    action();
    c.changed();
  }

  void _delete<T>(List<T> rows, T row, String label) {
    if (row is EditableSection &&
        d.unappliedPaste &&
        d.pasteSectionId == row.id) {
      d.error = 'Apply or discard this section’s pasted text first.';
      c.changed(clearError: false);
      return;
    }
    final undo = c.remove(rows, row);
    showUndo(context, message: '$label deleted', onUndo: undo);
  }

  Future<void> _deleteSection(EditableSection section) async {
    if (d.unappliedPaste && d.pasteSectionId == section.id) {
      _delete(d.sections, section, 'Section');
      return;
    }
    final name = section.name.isEmpty
        ? 'this unnamed section'
        : '“${section.name}”';
    final confirmed = await confirmCookdex(
      context,
      title: 'Delete section?',
      action: 'Delete section',
      destructive: true,
      content: Text('Delete $name and all its ingredients?'),
    );
    if (mounted && confirmed && d.sections.contains(section)) {
      _delete(d.sections, section, 'Section');
    }
  }

  void _removeSection(EditableSection section) {
    final undo = c.removeSection(section);
    if (undo != null) {
      showUndo(context, message: 'Section removed', onUndo: undo);
    }
  }

  Widget _heading(String text, {List<Widget> actions = const [], Key? key}) =>
      Padding(
        key: key,
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            Text(text, style: Theme.of(context).textTheme.titleLarge),
            ...actions,
          ],
        ),
      );
  Widget _field(
    String key,
    String label,
    String Function() readValue,
    ValueChanged<String> change, {
    bool multiline = true,
    bool timeField = false,
    String? hint,
    List<String> suggestions = const [],
  }) {
    final field = _EditorField(
      key: ValueKey(key),
      label: label,
      hint: hint,
      readValue: readValue,
      multiline: multiline,
      timeField: timeField,
      textCapitalization: const ['title', 'description', 'notes'].contains(key)
          ? TextCapitalization.sentences
          : TextCapitalization.none,
      suggestions: suggestions,
      aiLabel: !timeField && d.aiGuessedFields.contains(key)
          ? 'AI guess'
          : null,
      onChanged: (s) => _edit(() => change(s)),
    );
    return Padding(
      key: ValueKey('field-$key'),
      padding: const EdgeInsets.only(bottom: 12),
      child: timeField
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                field,
                if (d.aiGuessedFields.contains('${key}Time'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 0, 0),
                    child: Text(
                      'AI guess',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            )
          : field,
    );
  }

  Future<void> _rename(EditableSection section) async {
    final text = TextEditingController(text: section.name);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Section name'),
        content: PixelScrollScope(
          axis: Axis.horizontal,
          builder: (context) => DialogFieldPadding(
            child: TextField(
              scrollController: PrimaryScrollController.of(context),
              controller: text,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(ctx, text.text),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, text.text),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    // The dialog route may still animate out; dispose after its fields unmount.
    Future<void>.delayed(const Duration(seconds: 1), text.dispose);
    if (value != null && mounted) _change(() => section.name = value.trim());
  }

  Future<void> _addSection() async {
    final text = TextEditingController();
    final hasIngredients = d.sections.any((s) => s.rows.any((r) => !r.blank));
    final choice = await showDialog<(String, bool)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Section name'),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        buttonPadding: EdgeInsets.zero,
        content: PixelScrollScope(
          axis: Axis.horizontal,
          builder: (context) => DialogFieldPadding(
            child: TextField(
              scrollController: PrimaryScrollController.of(context),
              controller: text,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => Navigator.pop(ctx, (text.text.trim(), false)),
            ),
          ),
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => Navigator.pop(ctx, (text.text.trim(), false)),
            child: const Text('Add at end'),
          ),
          if (hasIngredients)
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 48),
              ),
              onPressed: () => Navigator.pop(ctx, (text.text.trim(), true)),
              child: const Text('Choose spot'),
            ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), text.dispose);
    if (!mounted || choice == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (choice.$2) {
      setState(() => _placingSection = choice.$1);
    } else {
      _insertSection(choice.$1);
    }
  }

  void _insertSection(String name, {EditableSection? source, int? rowIndex}) {
    final section = EditableSection(name: name);
    setState(() => _placingSection = null);
    _change(() {
      if (source == null) {
        section.rows.add(EditableIngredient());
        d.sections.add(section);
      } else {
        section.rows.addAll(source.rows.skip(rowIndex!));
        source.rows.removeRange(rowIndex, source.rows.length);
        if (section.rows.isEmpty) section.rows.add(EditableIngredient());
        d.sections.insert(d.sections.indexOf(source) + 1, section);
      }
    });
    unawaited(
      _revealEditorKey(_sectionKeys.putIfAbsent(section.id, GlobalKey.new)),
    );
  }

  Future<void> _revealEditorKey(
    GlobalKey key, {
    bool fromStart = false,
    Duration? duration,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    if (fromStart && _editorKeyRect(key) == null) {
      _scroll.jumpTo(0);
      await WidgetsBinding.instance.endOfFrame;
    }
    // Sliver children can be unbuilt. Advance by viewports until the new header
    // is laid out, then align it precisely rather than guessing row heights.
    while (mounted && _editorKeyRect(key) == null && _scroll.hasClients) {
      final position = _scroll.position;
      final next = (position.pixels + position.viewportDimension * .8).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (next == position.pixels) break;
      _scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    final target = key.currentContext;
    if (target != null && target.mounted && _editorKeyRect(key) != null) {
      await Scrollable.ensureVisible(
        target,
        alignment: 0,
        duration: duration ?? _sectionTransition,
      );
      // A zero-duration reveal schedules layout; measure return positions only
      // after the new scroll offset has actually been laid out.
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Widget _placementMarker(
    EditableSection section,
    int index, {
    bool line = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    final tightLabel = MediaQuery.textScalerOf(context).scale(14) > 20;
    final button = TextButton(
      key: ValueKey('section-spot-${section.id}-$index'),
      style: TextButton.styleFrom(
        foregroundColor: colors.tertiary,
        minimumSize: const Size(0, 48),
        padding: EdgeInsets.zero,
      ),
      onPressed: () {
        final atEnd = index == section.rows.length;
        _insertSection(
          _placingSection!,
          source: atEnd ? null : section,
          rowIndex: atEnd ? null : index,
        );
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.tertiary,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 12,
            vertical: tightLabel ? 0 : 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.add, size: 18, color: colors.onTertiary),
              const SizedBox(width: 6),
              Text(
                'Start here',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.onTertiary,
                  fontWeight: FontWeight.w700,
                  // Preserve enlarged glyphs while removing surplus leading
                  // inside the existing inter-row gap; the target stays 48dp.
                  height: tightLabel ? 1 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!line) return button;
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Divider(color: colors.tertiary, thickness: 1.5, height: 0),
          ),
          button,
        ],
      ),
    );
  }

  Widget _placementOverlay() {
    final width = MediaQuery.sizeOf(context).width;
    final contentWidth = width > 792 ? 760.0 : width - 32;
    final lastGroup = d.sections.where((s) => s.rows.isNotEmpty).lastOrNull;
    if (lastGroup == null) return const SizedBox.shrink();
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final section in d.sections)
            for (var i = 0; i < section.rows.length; i++)
              if (i + 1 < section.rows.length || section == lastGroup)
                CompositedTransformFollower(
                  link: _ingredientLinks.putIfAbsent(
                    section.rows[i].id,
                    LayerLink.new,
                  ),
                  showWhenUnlinked: false,
                  targetAnchor: Alignment.bottomCenter,
                  followerAnchor: Alignment.topCenter,
                  // Center the visible pill between the control glyphs and
                  // the next fields, while retaining its 48dp touch target.
                  offset: const Offset(0, -32),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: contentWidth - 16,
                      child: _placementMarker(section, i + 1),
                    ),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _placementBar() => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Tap where ${_placingSection!.isEmpty ? 'the section' : _placingSection} starts',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _placingSection = null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    ),
  );

  Rect? _sectionRect(EditableSection section) =>
      _editorKeyRect(_sectionKeys[section.id]);

  Rect? _editorKeyRect(GlobalKey? key) {
    final viewport = _editorViewportKey.currentContext?.findRenderObject();
    final header = key?.currentContext?.findRenderObject();
    if (viewport is! RenderBox || header is! RenderBox || !header.hasSize) {
      return null;
    }
    final rect =
        header.localToGlobal(Offset.zero, ancestor: viewport) & header.size;
    // Retained sliver children can have a size but no paint transform. Flutter
    // returns NaN coordinates for them; never feed those into an animation.
    return rect.isFinite && !rect.isEmpty ? rect : null;
  }

  void _startSectionDrag(EditableSection section, Offset pointer) {
    if (_sectionDrag || _placingSection != null) return;
    final viewport =
        _editorViewportKey.currentContext!.findRenderObject() as RenderBox;
    final held = _sectionRect(section);
    if (held == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.lightImpact();
    final index = d.sections.indexOf(section);
    final rects = <String, Rect>{};
    final visibleOrigins = <String>{};
    for (final (i, group) in d.sections.indexed) {
      final header = _sectionKeys[group.id]?.currentContext?.findRenderObject();
      final size = header is RenderBox && header.hasSize
          ? header.size
          : held.size;
      final painted = _sectionRect(group);
      if (painted != null && painted.overlaps(Offset.zero & viewport.size)) {
        visibleOrigins.add(group.id);
      }
      rects[group.id] =
          painted ??
          Rect.fromLTWH(
            held.left,
            i < index ? -size.height : viewport.size.height,
            size.width,
            size.height,
          );
    }
    final session = _SectionDragSession(
      section: section,
      order: d.sections.toList(),
      originalRects: rects,
      visibleOrigins: visibleOrigins,
      originalScroll: _scroll.offset,
      originalFocusSpace: _sectionFocusSpace,
      pointer: viewport.globalToLocal(pointer),
      viewport: viewport.size,
    );
    setState(() => _sectionDragSession = session);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(_sectionDragSession, session) &&
          !session.finishing) {
        _collapseSectionDrag(session);
      }
    });
  }

  void _collapseSectionDrag(_SectionDragSession session) {
    if (session.collapsed) return;
    final duration = _sectionTransition;
    setState(() => session.collapsed = true);
    session.collapseComplete = () async {
      // Start the clock on the frame that actually starts the transition.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(duration);
    }();
  }

  void _updateSectionDrag(Offset pointer) {
    final session = _sectionDragSession;
    if (session == null || session.finishing) return;
    final viewport =
        _editorViewportKey.currentContext!.findRenderObject() as RenderBox;
    session.updatePointer(viewport.globalToLocal(pointer));
  }

  Future<void> _finishSectionDrag({bool cancel = false}) async {
    final session = _sectionDragSession;
    if (session == null || session.finishing) return;
    final duration = _sectionTransition;
    session.finishing = true;
    if (cancel) {
      // The form never scrolled or shrank during the drag.
      session.returnRects = {
        for (final group in d.sections)
          group.id: session.visibleOrigins.contains(group.id)
              ? session.originalRects[group.id]!
              : session.slotRect(group),
      };
      session.visibleReturns = session.visibleOrigins;
    } else {
      // A quick release must not reposition a still-visible, half-collapsed
      // form. Finish collapse, position it while hidden, then expand.
      _collapseSectionDrag(session);
      await session.collapseComplete;
      if (!mounted || !identical(_sectionDragSession, session)) return;
      // Reserve only the trailing space needed to place even the last header
      // directly below the app bar. No collapsed-height scroll clamping occurs.
      setState(() => _sectionFocusSpace = session.viewport.height);
      c.reorder(
        d.sections,
        d.sections.indexOf(session.section),
        session.order.indexOf(session.section),
      );
      await _revealEditorKey(
        _sectionKeys[session.section.id]!,
        fromStart: true,
        duration: Duration.zero,
      );
      if (!mounted) return;
      final normalMax = _scroll.position.maxScrollExtent - _sectionFocusSpace;
      _sectionFocusSpace = (_scroll.offset - normalMax).clamp(
        0.0,
        session.viewport.height,
      );
      session.returnRects = {};
      for (final group in d.sections) {
        final rect = _sectionRect(group);
        if (rect != null && rect.overlaps(Offset.zero & session.viewport)) {
          session.visibleReturns.add(group.id);
          session.returnRects![group.id] = rect;
        } else {
          session.returnRects![group.id] = session.slotRect(group);
        }
      }
    }
    if (!mounted) return;
    setState(() => session.returning = true);
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(duration);
    if (!mounted || !identical(_sectionDragSession, session)) return;
    setState(() {
      _sectionDragSession = null;
      if (cancel) _sectionFocusSpace = session.originalFocusSpace;
    });
    if (cancel && _scroll.hasClients) _scroll.jumpTo(session.originalScroll);
    session.dispose();
  }

  Widget _sectionDragOverlay(_SectionDragSession session) => RepaintBoundary(
    child: IgnorePointer(
      child: ListenableBuilder(
        listenable: session,
        builder: (_, _) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (final group in session.order)
              if (group != session.section) _dragHeaderPosition(session, group),
            _dragHeaderPosition(session, session.section),
          ],
        ),
      ),
    ),
  );

  Widget _dragHeaderPosition(
    _SectionDragSession session,
    EditableSection section,
  ) {
    final held = section == session.section;
    final rect = session.returning
        ? session.returnRects![section.id]!
        : held
        ? session.heldRect
        : session.collapsed || !session.visibleOrigins.contains(section.id)
        ? session.slotRect(section)
        : session.originalRects[section.id]!;
    return AnimatedPositioned(
      key: ValueKey('drag-section-${section.id}'),
      duration: held && !session.returning ? Duration.zero : _sectionTransition,
      curve: Curves.easeInOut,
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: AnimatedOpacity(
        duration: _sectionTransition,
        // Let ingredient content clear before revealing offscreen headers;
        // remove those headers before ingredient content returns.
        curve: session.returning
            ? const Interval(0, .4, curve: Curves.easeInOut)
            : const Interval(.4, 1, curve: Curves.easeInOut),
        opacity:
            held ||
                (session.returning
                    ? session.visibleReturns.contains(section.id)
                    : session.collapsed ||
                          session.visibleOrigins.contains(section.id))
            ? 1
            : 0,
        child: Material(
          elevation: held && !session.returning ? 6 : 0,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surfaceContainer,
          animationDuration: _sectionTransition,
          child: LayoutBuilder(
            builder: (_, constraints) => FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                // Follow the animated height so compact previews shrink smoothly.
                width:
                    session.originalRects[section.id]!.width *
                    session.originalRects[section.id]!.height /
                    constraints.maxHeight,
                height: session.originalRects[section.id]!.height,
                child: session.headerWidgets.putIfAbsent(
                  section.id,
                  () => _sectionHeader(section, 0, overlay: true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHandle(EditableSection section, int index) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onLongPressStart: (details) =>
        _startSectionDrag(section, details.globalPosition),
    onLongPressMoveUpdate: (details) =>
        _updateSectionDrag(details.globalPosition),
    onLongPressEnd: (_) => unawaited(_finishSectionDrag()),
    onLongPressCancel: () => unawaited(_finishSectionDrag(cancel: true)),
    child: Semantics(
      label: 'Reorder section ${index + 1}',
      child: const SizedBox(
        width: 48,
        height: 48,
        child: Icon(Symbols.drag_handle),
      ),
    ),
  );

  Widget _sectionHeader(
    EditableSection section,
    int index, {
    bool overlay = false,
  }) => Material(
    color: section.name.isEmpty && !overlay
        ? Colors.transparent
        : Theme.of(context).colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(12),
    child: Row(
      children: [
        const SizedBox(width: 12),
        if (section.name.isNotEmpty || overlay)
          Expanded(
            child: Text(
              section.name.isEmpty ? 'Unsectioned ingredients' : section.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          )
        else
          const Spacer(),
        if (d.sections.length > 1)
          if (overlay)
            const SizedBox(
              width: 48,
              height: 48,
              child: Icon(Symbols.drag_handle),
            )
          else
            _sectionHandle(section, index),
        if (overlay)
          const SizedBox(width: 48, height: 48, child: Icon(Symbols.more_vert))
        else
          _sectionMenu(section, index),
      ],
    ),
  );

  PopupMenuItem<String> _menuItem(
    String value,
    String label, {
    bool destructive = false,
    bool enabled = true,
  }) => PopupMenuItem(
    value: value,
    enabled: enabled,
    child: Text(
      label,
      style: destructive
          ? TextStyle(color: Theme.of(context).colorScheme.error)
          : null,
    ),
  );
  Widget _drag(int index, String label) => ReorderableDelayedDragStartListener(
    index: index,
    child: Semantics(
      label: label,
      child: Container(
        color: Colors.transparent,
        width: 48,
        height: 48,
        child: const Icon(Symbols.drag_handle),
      ),
    ),
  );

  Widget _compactField(
    String key,
    String hint,
    String Function() readValue,
    ValueChanged<String> change, {
    bool multiline = false,
    List<String> suggestions = const [],
    List<String> Function()? suggestionProvider,
    String? semanticLabel,
    bool muted = false,
    Widget? editingAction,
    String? aiLabel,
  }) => _EditorField(
    key: ValueKey(key),
    label: hint,
    readValue: readValue,
    compact: true,
    muted: muted,
    semanticLabel: semanticLabel ?? hint,
    multiline: multiline,
    suggestions: suggestions,
    suggestionProvider: suggestionProvider,
    editingAction: editingAction,
    aiLabel: aiLabel,
    textCapitalization: semanticLabel?.startsWith('Step ') == true
        ? TextCapitalization.sentences
        : TextCapitalization.none,
    suggestionStrip: hint == 'Unit' || hint == 'Ingredient' || hint == 'Amount',
    onChanged: (s) => _edit(() => change(s)),
  );

  double _hintWidth(String hint, {double minimum = 0}) {
    final cached = _hintWidths[hint];
    if (cached != null) return cached < minimum ? minimum : cached;
    final text = TextPainter(
      text: TextSpan(text: hint, style: Theme.of(context).textTheme.bodyMedium),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Match the explicit compact hint style and retain room for both borders
    // as well as the 8dp padding on each side.
    final width = text.width + 24;
    _hintWidths[hint] = width;
    text.dispose();
    return width < minimum ? minimum : width;
  }

  Widget _ingredient(
    EditableSection section,
    EditableIngredient row,
    int index, {
    int? dragIndex,
  }) => Stack(
    key: ValueKey(row.id),
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final phone = MediaQuery.sizeOf(context).width < 600;
                final width = constraints.maxWidth;
                // The native field scrolls as the user types. Use its value
                // at focus entry for layout until that edit has finished.
                String value(String part, String current) {
                  final active = _suggestions.active;
                  return active != null &&
                          active.widget.key == ValueKey('${row.id}-$part')
                      ? active._valueAtFocus
                      : current;
                }

                final amount = value('amount', row.amount).trim();
                final unit = value('unit', row.unit).trim();
                final name = value('name', row.name).trim();
                // Text needs 12dp at the start and 15dp at the end in both
                // resting and active fields. _hintWidth includes 24dp.
                final amountWidth =
                    (_hintWidth(amount.isEmpty ? 'Amount' : amount) + 3)
                        .clamp(56.0, _hintWidth('1/2–1 1/2', minimum: 56) + 3)
                        .clamp(0.0, width);
                final sizedUnit = unit.startsWith('(');
                final unitWidth = sizedUnit
                    ? (_hintWidth(
                                phone ? '(14 oz) cans' : '(14 oz) containers',
                                minimum: _hintWidth(unit),
                              ) +
                              3)
                          .clamp(0.0, width)
                    : (_hintWidth(unit.isEmpty ? 'Unit' : unit) + 3)
                          .clamp(
                            64.0,
                            _hintWidth('tablespoons', minimum: 64) + 3,
                          )
                          .clamp(0.0, width);
                // Allow natural wrapping between words, without splitting
                // ordinary names such as "Olive" or "tomatoes" into fragments.
                final wordLimit = _hintWidth('tomatoes') + 5;
                var minName =
                    _hintWidth(name.isEmpty ? 'Ingredient' : 'Olive') + 5;
                for (final word in _word.allMatches(name).take(4)) {
                  final wordWidth = (_hintWidth(word[0]!) + 5).clamp(
                    0.0,
                    wordLimit,
                  );
                  if (wordWidth > minName) minName = wordWidth;
                }
                final remaining = width - amountWidth - unitWidth - 12;
                final nameWidth =
                    remaining >= minName.clamp(88.0, double.infinity)
                    ? remaining
                    : width;
                // Keep field elements mounted when resizing changes the layout.
                return Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    SizedBox(
                      width: amountWidth,
                      child: _compactField(
                        '${row.id}-amount',
                        'Amount',
                        () => row.amount,
                        (s) {
                          if (s != row.amount &&
                              (row.aiGuessedAmount ||
                                  row.prepNote.trim() == amountGuessNote)) {
                            setState(() {
                              row.aiGuessedAmount = false;
                              row.prepNote = row.prepNote
                                  .replaceFirst(amountGuessNote, '')
                                  .trim();
                              if (row.prepNote.isEmpty) row.showNote = false;
                            });
                          }
                          row.amount = s;
                        },
                      ),
                    ),
                    SizedBox(
                      width: unitWidth,
                      child: _compactField(
                        '${row.id}-unit',
                        'Unit',
                        () => row.unit,
                        (s) => row.unit = s,
                        suggestionProvider: () => [
                          ..._usedUnits,
                          ...standardUnits.where(
                            (unit) => !_usedUnits.any(
                              (used) => used.toLowerCase() == unit,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: nameWidth,
                      child: _compactField(
                        '${row.id}-name',
                        'Ingredient',
                        () => row.name,
                        (s) => row.name = s,
                        multiline: true,
                        suggestions: _ingredientNames,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (row.aiGuessedAmount && !row.prepNote.contains(amountGuessNote))
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    amountGuessNote,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            if (row.showNote || row.prepNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _compactField(
                  '${row.id}-note',
                  'Prep note',
                  () => row.prepNote,
                  (s) => row.prepNote = s,
                  multiline: true,
                  muted: true,
                ),
              ),
            IgnorePointer(
              ignoring: _placingSection != null,
              child: Opacity(
                opacity: _placingSection == null ? 1 : .28,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showNote = !row.showNote && row.prepNote.isEmpty;
                    final noteWidth = (_hintWidth('+ Note') - 8).clamp(
                      48.0,
                      double.infinity,
                    );
                    final optionalWidth = (_hintWidth('Optional') - 24 + 32)
                        .ceilToDouble();
                    final rightWidth = optionalWidth + 12 + 48;
                    final controlsWidth = constraints.maxWidth.clamp(
                      rightWidth + 48,
                      double.infinity,
                    );
                    final noteFits =
                        noteWidth + 48 + rightWidth <= constraints.maxWidth;
                    // Preserve the centered grip when it fits; move it left before
                    // Optional rather than wrapping the action group onto another row.
                    final gripLeft = ((controlsWidth - 48) / 2).clamp(
                      noteFits ? noteWidth : 0.0,
                      controlsWidth - rightWidth - 48,
                    );
                    final note = TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: () => _change(() => row.showNote = true),
                      child: const Text('+ Note'),
                    );
                    final controlsRow = SizedBox(
                      width: controlsWidth,
                      child: Row(
                        key: ValueKey('${row.id}-controls'),
                        children: [
                          SizedBox(
                            width: gripLeft,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: showNote && noteFits ? note : null,
                            ),
                          ),
                          _drag(
                            dragIndex ?? index,
                            'Reorder ingredient ${index + 1}',
                          ),
                          const Spacer(),
                          SizedBox(
                            width: optionalWidth,
                            height: 48,
                            child: InkWell(
                              onTap: () =>
                                  _change(() => row.optional = !row.optional),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Checkbox(
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      value: row.optional,
                                      semanticLabel:
                                          'Optional ingredient ${index + 1}',
                                      onChanged: (value) => _change(
                                        () => row.optional = value ?? false,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Optional',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'Delete ingredient ${index + 1}',
                            onPressed: () =>
                                _delete(section.rows, row, 'Ingredient'),
                            icon: Icon(
                              Symbols.delete,
                              color: mutedDeleteColor(
                                Theme.of(context).colorScheme,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                    final controls = controlsWidth > constraints.maxWidth
                        ? PixelSingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: controlsRow,
                          )
                        : controlsRow;
                    // Only the independent add-note action may need its own line at
                    // very large text sizes. Grip, Optional and Delete never separate.
                    return showNote && !noteFits
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: note,
                              ),
                              controls,
                            ],
                          )
                        : controls;
                  },
                ),
              ),
            ),
            Opacity(
              opacity:
                  _placingSection != null &&
                      (index + 1 < section.rows.length ||
                          section ==
                              d.sections.lastWhere((s) => s.rows.isNotEmpty))
                  ? 0
                  : 1,
              child: const Divider(),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _sectionMenu(EditableSection section, int index) =>
      PopupMenuButton<String>(
        enabled: _placingSection == null,
        tooltip: 'Section ${index + 1} options',
        icon: const Icon(Symbols.more_vert),
        onSelected: (value) {
          switch (value) {
            case 'rename':
              _rename(section);
            case 'up':
              c.move(d.sections, section, -1);
            case 'down':
              c.move(d.sections, section, 1);
            case 'delete':
              _deleteSection(section);
            case 'remove':
              _removeSection(section);
          }
        },
        itemBuilder: (_) => [
          _menuItem('rename', 'Rename'),
          _menuItem('up', 'Move up', enabled: index > 0),
          _menuItem(
            'down',
            'Move down',
            enabled: index + 1 < d.sections.length,
          ),
          _menuItem('remove', 'Remove section', enabled: index > 0),
          _menuItem('delete', 'Delete section', destructive: true),
        ],
      );

  List<(EditableSection, Widget Function(int), EditableIngredient?)>
  _ingredientEntries() {
    final entries =
        <(EditableSection, Widget Function(int), EditableIngredient?)>[];
    for (
      var sectionIndex = 0;
      sectionIndex < d.sections.length;
      sectionIndex++
    ) {
      final index = sectionIndex;
      final section = d.sections[index];
      if (section.name.isNotEmpty || d.sections.length > 1) {
        entries.add((
          section,
          (_) => SizedBox(
            key: ValueKey(section.id),
            child: Stack(
              children: [
                Opacity(
                  opacity:
                      _placingSection != null &&
                          index == 0 &&
                          section.name.isEmpty
                      ? 0
                      : 1,
                  child: IgnorePointer(
                    ignoring: _placingSection != null,
                    child: _sectionHeader(section, index),
                  ),
                ),
                if (_placingSection != null &&
                    index == 0 &&
                    section.name.isEmpty &&
                    section.rows.isNotEmpty)
                  Positioned.fill(child: _placementMarker(section, 0)),
              ],
            ),
          ),
          null,
        ));
      }
      for (var i = 0; i < section.rows.length; i++) {
        final rowIndex = i;
        final row = section.rows[i];
        entries.add((
          section,
          (flatIndex) =>
              _ingredient(section, row, rowIndex, dragIndex: flatIndex),
          row,
        ));
      }
      {
        entries.add((
          section,
          (_) => KeyedSubtree(
            key: ValueKey('${section.id}-actions'),
            child: IgnorePointer(
              ignoring: _placingSection != null,
              child: Opacity(
                opacity: _placingSection == null ? 1 : .28,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _change(
                          () => section.rows.add(EditableIngredient()),
                        ),
                        icon: const Icon(Symbols.add),
                        label: const Text('Ingredient'),
                      ),
                      TextButton.icon(
                        onPressed: () => _paste('ingredients', section),
                        icon: const Icon(Symbols.content_paste),
                        label: const Text('Paste ingredients'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          null,
        ));
      }
    }
    return entries;
  }

  void _reorderIngredientEntries(
    List<(EditableSection, Widget Function(int), EditableIngredient?)> entries,
    int a,
    int b,
  ) {
    final source = entries[a];
    final target = entries[b.clamp(0, entries.length - 1)];
    if (source.$3 != null) {
      // onReorderItem supplies the final flat index after removing the source.
      // Section labels and action rows are real drop boundaries, including for
      // empty sections and the unnamed group. Keep the row identity and raw text.
      final reordered = entries.toList();
      reordered.insert(b, reordered.removeAt(a));
      final preceding = reordered.take(b).toList();
      final destination = preceding.isEmpty
          ? d.sections.first
          : preceding.last.$1;
      final rowIndex = preceding
          .where((entry) => entry.$1 == destination && entry.$3 != null)
          .length;
      _change(() {
        source.$1.rows.remove(source.$3);
        destination.rows.insert(rowIndex, source.$3!);
      });
    } else if (a == entries.indexWhere((e) => e.$1 == source.$1)) {
      c.reorder(
        d.sections,
        d.sections.indexOf(source.$1),
        d.sections.indexOf(target.$1),
      );
    }
  }

  Widget _step(EditableStep step, int index) => Padding(
    key: ValueKey(step.id),
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              _drag(index, 'Reorder step ${index + 1}'),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _compactField(
            '${step.id}-text',
            '',
            () => step.text,
            (s) => step.text = s,
            multiline: true,
            semanticLabel: 'Step ${index + 1}',
            aiLabel: step.aiGuess ? 'AI-written' : null,
            editingAction: IconButton(
              tooltip: 'Delete step ${index + 1}',
              onPressed: () => _delete(d.steps, step, 'Step'),
              icon: Icon(
                Symbols.delete,
                color: mutedDeleteColor(Theme.of(context).colorScheme),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _paste(String kind, [EditableSection? section]) async {
    if (d.unappliedPaste &&
        (d.pasteKind != kind || d.pasteSectionId != section?.id)) {
      if (!await confirmCookdex(
        context,
        title: 'Discard unapplied paste?',
        action: 'Discard',
        destructive: true,
      )) {
        return;
      }
      c.clearPaste();
    }
    d.pasteKind = kind;
    d.pasteSectionId = section?.id;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PasteDialog(controller: c, section: section),
    );
    if (mounted && d.pasteText.isEmpty) c.clearPaste();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => PredictiveFormBackGuard(
      enabled: !c.saving && !_backDialog && !_leaving,
      onBack: _back,
      child: PopScope(
        canPop: _leaving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) {
                  _back();
                  return null;
                },
              ),
            },
            child: _EditorSuggestionsScope(
              suggestions: _suggestions,
              child: Scaffold(
                appBar: _placingSection != null
                    ? AppBar(
                        automaticallyImplyLeading: false,
                        titleSpacing: 0,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                        title: _placementBar(),
                      )
                    : AppBar(
                        leading: IconButton(
                          tooltip: 'Back',
                          onPressed: c.saving ? null : _back,
                          icon: const Icon(Symbols.arrow_back),
                        ),
                        title: Text(
                          d.smartCreated
                              ? 'Review recipe'
                              : d.imported
                              ? 'Review import'
                              : d.base == null
                              ? 'Write a recipe'
                              : 'Edit recipe',
                        ),
                        actions: [
                          TextButton(
                            style: c.saving
                                ? TextButton.styleFrom(
                                    disabledForegroundColor:
                                        Theme.of(context).colorScheme.onSurface,
                                  )
                                : null,
                            onPressed:
                                c.saving ||
                                    _sectionDrag ||
                                    _placingSection != null
                                ? null
                                : _save,
                            child: Text(
                              c.saving
                                  ? 'Saving…'
                                  : d.stale
                                  ? 'Save copy'
                                  : 'Save',
                            ),
                          ),
                        ],
                      ),
                body: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          key: _editorViewportKey,
                          fit: StackFit.expand,
                          children: [
                            AnimatedOpacity(
                              opacity:
                                  _sectionDragSession?.collapsed == true &&
                                      _sectionDragSession?.returning != true
                                  ? 0
                                  : 1,
                              duration: _sectionTransition,
                              curve: _sectionDragSession?.returning == true
                                  ? const Interval(
                                      .6,
                                      1,
                                      curve: Curves.easeInOut,
                                    )
                                  : const Interval(
                                      0,
                                      .4,
                                      curve: Curves.easeInOut,
                                    ),
                              child: AbsorbPointer(
                                absorbing: c.saving || _sectionDrag,
                                child: Builder(
                                  builder: (context) {
                                    final width = MediaQuery.sizeOf(context)
                                        .width;
                                    final inset = width > 792
                                        ? (width - 760) / 2
                                        : 16.0;
                                    final entries = _ingredientEntries();
                                    return _EditorScrollView(
                                      controller: _scroll,
                                      onPointerCancel: (_) => unawaited(
                                        _finishSectionDrag(cancel: true),
                                      ),
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .manual,
                                      slivers: [
                                        SliverPadding(
                                          padding: EdgeInsets.fromLTRB(
                                            inset,
                                            12,
                                            inset,
                                            0,
                                          ),
                                          sliver: BuiltSliverList(
                                            children: [
                                              if (c.saving &&
                                                  widget.onSmartCreateSaved ==
                                                      null)
                                                const LinearProgressIndicator(),
                                              if (d.smartCreated)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 16,
                                                      ),
                                                  child: ListTile(
                                                    tileColor: Theme.of(context)
                                                        .colorScheme
                                                        .tertiaryContainer,
                                                    textColor: Theme.of(context)
                                                        .colorScheme
                                                        .onTertiaryContainer,
                                                    iconColor: Theme.of(context)
                                                        .colorScheme
                                                        .onTertiaryContainer,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            16,
                                                          ),
                                                    ),
                                                    leading: const Icon(
                                                      Symbols.auto_awesome,
                                                    ),
                                                    title: const Text(
                                                      'Made with Smart Create',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    subtitle: Text(
                                                      [
                                                        'Check it over before saving. Amounts and times are its best guess.',
                                                        if (d.createWarning !=
                                                            null)
                                                          d.createWarning!,
                                                      ].join('\n'),
                                                    ),
                                                  ),
                                                )
                                              else if (d.imported)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 12,
                                                      ),
                                                  child: Text(
                                                    d.importSourceLine.isEmpty
                                                        ? 'Imported, review and save'
                                                        : d.importSourceLine,
                                                  ),
                                                ),
                                              if (d.aiRewrittenSteps)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  child: Text(
                                                    "Google's AI wouldn't copy this recipe word for word, so it rewrote the steps in its own words. Check them against the original before saving.",
                                                  ),
                                                ),
                                              for (final warning
                                                  in d.importWarnings)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 8,
                                                      ),
                                                  child: Text(
                                                    warning,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall,
                                                  ),
                                                ),
                                              if (d.stale)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  child: Text(
                                                    'Original changed. Save this draft as a copy.',
                                                  ),
                                                ),
                                              if (d.error != null)
                                                Semantics(
                                                  liveRegion: true,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 12,
                                                        ),
                                                    child: Text(
                                                      d.error!,
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              if (c.persistenceError != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 12,
                                                      ),
                                                  child: Text(
                                                    c.persistenceError!,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                                  ),
                                                ),
                                              if (d.unappliedPaste)
                                                Card(
                                                  margin:
                                                      const EdgeInsets.fromLTRB(
                                                        4,
                                                        4,
                                                        4,
                                                        16,
                                                      ),
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.all(
                                                          12,
                                                        ),
                                                    child: Wrap(
                                                      crossAxisAlignment:
                                                          WrapCrossAlignment
                                                              .center,
                                                      spacing: 8,
                                                      children: [
                                                        const Text(
                                                          'Unapplied paste',
                                                        ),
                                                        TextButton(
                                                          onPressed: () => _paste(
                                                            d.pasteKind!,
                                                            d.sections
                                                                .where(
                                                                  (s) =>
                                                                      s.id ==
                                                                      d.pasteSectionId,
                                                                )
                                                                .firstOrNull,
                                                          ),
                                                          child: const Text(
                                                            'Review',
                                                          ),
                                                        ),
                                                        TextButton(
                                                          style: TextButton.styleFrom(
                                                            foregroundColor:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .error,
                                                          ),
                                                          onPressed:
                                                              c.clearPaste,
                                                          child: const Text(
                                                            'Discard',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              _field(
                                                'title',
                                                'Title',
                                                () => d.title,
                                                (s) => d.title = s,
                                              ),
                                              _field(
                                                'description',
                                                'Description',
                                                () => d.description,
                                                (s) => d.description = s,
                                                multiline: true,
                                              ),
                                              _field(
                                                'servings',
                                                'Makes',
                                                () => d.servings,
                                                (s) => d.servings = s,
                                                hint: '4 servings or 12 tortillas',
                                              ),
                                              LayoutBuilder(
                                                builder: (context, constraints) {
                                                  // Outlined labels render at 75% of body size.
                                                  // Reserve the actual 16dp side insets and
                                                  // 4dp border gap on each side of the label.
                                                  var minimum = 48.0;
                                                  for (final title in [
                                                    'Prep time',
                                                    'Cook time',
                                                    'Total time',
                                                  ]) {
                                                    final label = TextPainter(
                                                      text: TextSpan(
                                                        text: title,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyLarge,
                                                      ),
                                                      textDirection:
                                                          Directionality.of(
                                                            context,
                                                          ),
                                                      textScaler:
                                                          MediaQuery.textScalerOf(
                                                            context,
                                                          ),
                                                    )..layout();
                                                    final width =
                                                        label.width * .75 + 40;
                                                    if (width > minimum) {
                                                      minimum = width;
                                                    }
                                                    label.dispose();
                                                  }
                                                  final columns =
                                                      ((constraints.maxWidth +
                                                                  12) /
                                                              (minimum + 12))
                                                          .floor()
                                                          .clamp(1, 3);
                                                  final width =
                                                      (constraints.maxWidth -
                                                          12 * (columns - 1)) /
                                                      columns;
                                                  return Wrap(
                                                    key: const ValueKey(
                                                      'recipe-times',
                                                    ),
                                                    spacing: 12,
                                                    children: [
                                                      SizedBox(
                                                        width: width,
                                                        child: _field(
                                                          'prep',
                                                          'Prep time',
                                                          () => d.prepTime,
                                                          (s) => d.prepTime = s,
                                                          multiline: false,
                                                          timeField: true,
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: width,
                                                        child: _field(
                                                          'cook',
                                                          'Cook time',
                                                          () => d.cookTime,
                                                          (s) => d.cookTime = s,
                                                          multiline: false,
                                                          timeField: true,
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        width: width,
                                                        child: _field(
                                                          'total',
                                                          'Total time',
                                                          () => d.totalTime,
                                                          (s) =>
                                                              d.totalTime = s,
                                                          multiline: false,
                                                          timeField: true,
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                              _heading(
                                                'Tags',
                                                actions: [
                                                  if (d.aiGuessedFields
                                                      .contains('tags'))
                                                    Text(
                                                      'AI guess',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall,
                                                    ),
                                                ],
                                              ),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 4,
                                                children: [
                                                  for (final tag
                                                      in normalizeTags(d.tags))
                                                    InputChip(
                                                      label: Text(tag),
                                                      onDeleted: () => _change(
                                                        () => d.tags.removeWhere(
                                                          (t) =>
                                                              normalizeNameWhitespace(
                                                                t,
                                                              ) ==
                                                              tag,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              _EditorField(
                                                key: const ValueKey(
                                                  'tag-input',
                                                ),
                                                suggestionStrip: true,
                                                label: 'Add tag',
                                                readValue: () => d.tagInput,
                                                suggestions: _tags
                                                    .where(
                                                      (s) => !d.tags.any(
                                                        (t) =>
                                                            t.toLowerCase() ==
                                                            s.toLowerCase(),
                                                      ),
                                                    )
                                                    .toList(),
                                                onChanged: (s) =>
                                                    _edit(() => d.tagInput = s),
                                                onSubmitted: (s) => c.addTag(
                                                  s,
                                                  widget.tagSuggestions,
                                                ),
                                                onSelected: (s) => c.addTag(
                                                  s,
                                                  widget.tagSuggestions,
                                                ),
                                                suffix: IconButton(
                                                  tooltip: 'Add tag',
                                                  icon: const Icon(Symbols.add),
                                                  onPressed: () => c.addTag(
                                                    d.tagInput,
                                                    widget.tagSuggestions,
                                                  ),
                                                ),
                                              ),
                                              _heading(
                                                'Ingredients',
                                                key: _ingredientsHeadingKey,
                                                actions: [
                                                  Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (_placingSection !=
                                                              null &&
                                                          d.sections.length ==
                                                              1 &&
                                                          d
                                                              .sections
                                                              .first
                                                              .name
                                                              .isEmpty)
                                                        _placementMarker(
                                                          d.sections.first,
                                                          0,
                                                          line: false,
                                                        )
                                                      else
                                                        TextButton.icon(
                                                          onPressed:
                                                              _placingSection ==
                                                                  null
                                                              ? _addSection
                                                              : null,
                                                          icon: const Icon(
                                                            Symbols.add,
                                                          ),
                                                          label: const Text(
                                                            'Section',
                                                          ),
                                                        ),
                                                      if (d.sections.length ==
                                                              1 &&
                                                          d
                                                              .sections
                                                              .single
                                                              .name
                                                              .isEmpty)
                                                        _sectionMenu(
                                                          d.sections.single,
                                                          0,
                                                        ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        SliverPadding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: inset,
                                          ),
                                          sliver: SliverReorderableList(
                                            key: _ingredientListKey,
                                            onReorderStart: (_) =>
                                                HapticFeedback.lightImpact(),
                                            proxyDecorator: (
                                              child,
                                              index,
                                              animation,
                                            ) => Material(child: child),
                                            itemCount: entries.length,
                                            itemBuilder: (_, i) {
                                              final child = entries[i].$2(i);
                                              final section = entries[i].$1;
                                              final header =
                                                  child.key ==
                                                  ValueKey(section.id);
                                              return KeepBuilt(
                                                key: ValueKey((
                                                  'built-ingredient',
                                                  child.key,
                                                )),
                                                child: Opacity(
                                                  opacity:
                                                      header && _sectionDrag
                                                      ? 0
                                                      : 1,
                                                  child: KeyedSubtree(
                                                    key: header
                                                        ? _sectionKeys
                                                              .putIfAbsent(
                                                                section.id,
                                                                GlobalKey.new,
                                                              )
                                                        : null,
                                                    child: entries[i].$3 != null
                                                        ? CompositedTransformTarget(
                                                            link:
                                                                _ingredientLinks
                                                                    .putIfAbsent(
                                                                      entries[i]
                                                                          .$3!
                                                                          .id,
                                                                      LayerLink
                                                                          .new,
                                                                    ),
                                                            child: child,
                                                          )
                                                        : child,
                                                  ),
                                                ),
                                              );
                                            },
                                            onReorderItem: (a, b) =>
                                                _reorderIngredientEntries(
                                                  entries,
                                                  a,
                                                  b,
                                                ),
                                          ),
                                        ),
                                        SliverOpacity(
                                          opacity:
                                              _sectionDrag &&
                                                  _sectionDragSession
                                                          ?.returning !=
                                                      true
                                              ? 0
                                              : 1,
                                          sliver: SliverMainAxisGroup(
                                            slivers: [
                                              SliverPadding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: inset,
                                                ),
                                                sliver: SliverToBoxAdapter(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      _heading(
                                                        'Steps',
                                                        actions: [
                                                          TextButton.icon(
                                                            onPressed: () =>
                                                                _paste('steps'),
                                                            icon: const Icon(
                                                              Symbols
                                                                  .content_paste,
                                                            ),
                                                            label: const Text(
                                                              'Paste steps',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              SliverPadding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: inset,
                                                ),
                                                sliver: SliverReorderableList(
                                                  onReorderStart: (_) =>
                                                      HapticFeedback.lightImpact(),
                                                  proxyDecorator: (
                                                    child,
                                                    index,
                                                    animation,
                                                  ) => Material(child: child),
                                                  itemCount: d.steps.length,
                                                  itemBuilder: (_, i) =>
                                                      KeepBuilt(
                                                        key: ValueKey((
                                                          'built-step',
                                                          d.steps[i].id,
                                                        )),
                                                        child: _step(
                                                          d.steps[i],
                                                          i,
                                                        ),
                                                      ),
                                                  onReorderItem: (a, b) =>
                                                      c.reorder(d.steps, a, b),
                                                ),
                                              ),
                                              SliverPadding(
                                                padding: EdgeInsets.fromLTRB(
                                                  inset,
                                                  0,
                                                  inset,
                                                  32,
                                                ),
                                                sliver: BuiltSliverList(
                                                  children: [
                                                    Align(
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: TextButton.icon(
                                                        onPressed: () =>
                                                            _change(
                                                              () => d.steps.add(
                                                                EditableStep(
                                                                  '',
                                                                ),
                                                              ),
                                                            ),
                                                        icon: const Icon(
                                                          Symbols.add,
                                                        ),
                                                        label: const Text(
                                                          'Step',
                                                        ),
                                                      ),
                                                    ),
                                                    _heading('Notes'),
                                                    _field(
                                                      'notes',
                                                      'Notes',
                                                      () => d.notes,
                                                      (s) => d.notes = s,
                                                      multiline: true,
                                                    ),
                                                    _field(
                                                      'source',
                                                      'Source',
                                                      () => d.source,
                                                      (s) => d.source = s,
                                                      hint: 'Book, person or link',
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_sectionFocusSpace > 0)
                                          SliverToBoxAdapter(
                                            child: SizedBox(
                                              height: _sectionFocusSpace,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            if (_placingSection != null)
                              Positioned.fill(child: _placementOverlay()),
                            if (_sectionDragSession case final session?)
                              Positioned.fill(
                                child: _sectionDragOverlay(session),
                              ),
                          ],
                        ),
                      ),
                      MeasureHeight(
                        onChanged: (height) {
                          if (height > 0) {
                            _suggestions.active?.revealAboveSuggestions();
                          }
                        },
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _keyboardVisible,
                          builder: (_, visible, _) => _EditorSuggestionStrip(
                            suggestions: _suggestions,
                            keyboardVisible: visible,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _SectionDragSession extends ChangeNotifier {
  _SectionDragSession({
    required this.section,
    required this.order,
    required this.originalRects,
    required this.visibleOrigins,
    required this.originalScroll,
    required this.originalFocusSpace,
    required this.pointer,
    required this.viewport,
  }) {
    final held = originalRects[section.id]!;
    pointerOffset = pointer - held.topLeft;
    rawHeight =
        order.fold(0.0, (h, s) => h + originalRects[s.id]!.height + 16) - 16;
    overviewScale = ((viewport.height - 48) / rawHeight).clamp(.01, 1.0);
    var prefix = 0.0;
    for (final group in order.take(order.indexOf(section))) {
      prefix += originalRects[group.id]!.height + 16;
    }
    top = (held.top - prefix * overviewScale).clamp(
      24.0,
      (viewport.height - 24 - listHeight).clamp(24.0, double.infinity),
    );
    _refreshSlots();
    // Fit the overview beside the held header's vertical band when its former
    // neighbors would otherwise be off screen or covered by the drag proxy.
    if (order.any(
      (s) => s != section && slotRect(s).overlaps(held.inflate(8)),
    )) {
      final below = (viewport.height - 24 - held.bottom - 16).clamp(
        0.0,
        double.infinity,
      );
      final above = (held.top - 16 - 24).clamp(0.0, double.infinity);
      final useBelow =
          below >= listHeight || (above < listHeight && below >= above);
      final available = useBelow ? below : above;
      overviewScale = (available / rawHeight).clamp(.01, 1.0);
      top = useBelow ? held.bottom + 16 : held.top - 16 - listHeight;
      _refreshSlots();
    }
  }
  final EditableSection section;
  final List<EditableSection> order;
  final Map<String, Rect> originalRects;
  final Set<String> visibleOrigins;
  Set<String> visibleReturns = {};
  final double originalScroll, originalFocusSpace;
  final Size viewport;
  late final Offset pointerOffset;
  late final double rawHeight;
  Offset pointer;
  late double top, overviewScale;
  final _slots = <String, Rect>{};
  final headerWidgets = <String, Widget>{};
  bool collapsed = false, finishing = false, returning = false;
  Future<void>? collapseComplete;
  Map<String, Rect>? returnRects;
  Rect get heldRect {
    final original = originalRects[section.id]!;
    return Rect.fromLTWH(
      original.left,
      (pointer.dy - pointerOffset.dy).clamp(
        0.0,
        (viewport.height - original.height).clamp(0.0, double.infinity),
      ),
      original.width,
      original.height,
    );
  }

  double get listHeight => rawHeight * overviewScale;
  Rect slotRect(EditableSection section) => _slots[section.id]!;
  void _refreshSlots() {
    var y = top;
    for (final group in order) {
      final rect = originalRects[group.id]!;
      _slots[group.id] = Rect.fromLTWH(
        rect.left,
        y,
        rect.width,
        rect.height * overviewScale,
      );
      y += (rect.height + 16) * overviewScale;
    }
  }

  void updatePointer(Offset value) {
    if (finishing || pointer.dy == value.dy) return;
    pointer = Offset(pointer.dx, value.dy);
    final from = order.indexOf(section);
    var to = from;
    final center = heldRect.center.dy;
    for (var i = 0; i < order.length; i++) {
      final middle = slotRect(order[i]).center.dy;
      if (i < from && center < middle && i < to) to = i;
      if (i > from && center > middle) to = i;
    }
    if (to != from) {
      order.insert(to, order.removeAt(from));
      _refreshSlots();
    }
    notifyListeners();
  }
}

class _EditorScrollView extends StatelessWidget {
  const _EditorScrollView({
    required this.slivers,
    required this.keyboardDismissBehavior,
    required this.controller,
    required this.onPointerCancel,
  });
  final ScrollController controller;
  final PointerCancelEventListener onPointerCancel;
  final List<Widget> slivers;
  final ScrollViewKeyboardDismissBehavior keyboardDismissBehavior;

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollStartNotification>(
    onNotification: (notification) {
      if (notification.depth == 0 &&
          notification.dragDetails != null &&
          View.of(context).viewInsets.bottom > 0) {
        // Like Android's keyboard Back action: hide the IME without unfocusing
        // and disposing the edited row's native undo/composition state.
        unawaited(
          SystemChannels.textInput.invokeMethod<void>('TextInput.hide'),
        );
      }
      return false;
    },
    child: Listener(
      onPointerCancel: onPointerCancel,
      child: IdleBuildAhead(
        allRows: true,
        builder: (context, cache) => PixelCustomScrollView(
          controller: controller,
          scrollCacheExtent: ScrollCacheExtent.pixels(cache),
          slivers: slivers,
          keyboardDismissBehavior: keyboardDismissBehavior,
        ),
      ),
    ),
  );
}

/// Review is a separate route: Back closes it without mutating the draft.
class NameMatchReview extends StatefulWidget {
  const NameMatchReview({super.key, required this.matches});
  final List<NameMatch> matches;
  @override
  State<NameMatchReview> createState() => _NameMatchReviewState();
}

class _NameMatchReviewState extends State<NameMatchReview> {
  late final checked = {for (var i = 0; i < widget.matches.length; i++) i};
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Match library names?'),
    content: SizedBox(
      width: 440,
      child: PixelSingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Use familiar spellings for the checked names.'),
            const SizedBox(height: 12),
            for (final (index, match) in widget.matches.indexed)
              CheckboxListTile(
                key: ValueKey('name-match-$index'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: checked.contains(index),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    checked.add(index);
                  } else {
                    checked.remove(index);
                  }
                }),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '${match.entered} '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(
                          Symbols.arrow_forward,
                          size: MediaQuery.textScalerOf(context).scale(16),
                        ),
                      ),
                      TextSpan(text: ' ${match.preferred}'),
                    ],
                  ),
                  semanticsLabel: '${match.entered} to ${match.preferred}',
                ),
                subtitle: Text(match.tag ? 'Tag' : 'Ingredient'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Back'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, checked),
        child: const Text('Save'),
      ),
    ],
  );
}

/// Ranks collection values by use, with stable ordering for ties and no duplicates.
List<String> rankEditorSuggestions(
  Iterable<String> values, {
  bool lowercase = false,
}) {
  final counts = <String, int>{};
  final labels = <String, String>{};
  for (final value in values) {
    final label = value.trim();
    if (label.isEmpty) continue;
    final key = label.toLowerCase();
    labels.putIfAbsent(key, () => lowercase ? key : label);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final keys = counts.keys.toList();
  final order = {for (var i = 0; i < keys.length; i++) keys[i]: i};
  keys.sort((a, b) {
    final usage = counts[b]!.compareTo(counts[a]!);
    return usage == 0 ? order[a]!.compareTo(order[b]!) : usage;
  });
  return keys.map((key) => labels[key]!).toList();
}

class _EditorSuggestions extends ChangeNotifier {
  final activatedFields = <Key>{};
  _EditorFieldState? active;
  bool _disposed = false;

  void refresh(_EditorFieldState field) {
    if (_disposed) return;
    if (field.mounted && field._focus.hasFocus) {
      active = field;
    } else if (identical(active, field)) {
      active = null;
    } else {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    active = null;
    super.dispose();
  }
}

class _EditorSuggestionsScope extends InheritedWidget {
  const _EditorSuggestionsScope({
    required this.suggestions,
    required super.child,
  });
  final _EditorSuggestions suggestions;
  @override
  bool updateShouldNotify(_EditorSuggestionsScope oldWidget) =>
      suggestions != oldWidget.suggestions;
}

class _EditorSuggestionStrip extends StatelessWidget {
  const _EditorSuggestionStrip({
    required this.suggestions,
    required this.keyboardVisible,
  });
  final bool keyboardVisible;
  final _EditorSuggestions suggestions;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: suggestions,
    builder: (context, _) {
      final field = suggestions.active;
      if (field == null ||
          (Theme.of(context).platform == TargetPlatform.android &&
              !keyboardVisible) ||
          !field.mounted ||
          !field._focus.hasFocus ||
          !field.widget.suggestionStrip) {
        return const SizedBox.shrink();
      }
      final amount = field.widget.label == 'Amount';
      final query = field._text.text.trim().toLowerCase();
      final options = amount
          ? const ['to taste']
          : (field.widget.suggestionProvider?.call() ??
                    field.widget.suggestions)
                .where((option) => option.toLowerCase().contains(query))
                .toList();
      return TextFieldTapRegion(
        child: Material(
          key: const ValueKey('editor-suggestion-strip'),
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: _SuggestionOptions(
            key: ObjectKey(field),
            options: options,
            onSelected: field.select,
          ),
        ),
      );
    },
  );
}

/// Paint only the visible strip. Prepare nearby chips after its first frame;
/// retain a bounded set so reversing a drag does not recreate every chip.
class _SuggestionOptions extends StatefulWidget {
  const _SuggestionOptions({
    super.key,
    required this.options,
    required this.onSelected,
  });
  final List<String> options;
  final ValueChanged<String> onSelected;
  @override
  State<_SuggestionOptions> createState() => _SuggestionOptionsState();
}

class _SuggestionOptionsState extends State<_SuggestionOptions> {
  final _retained = BuiltRowBudget(64);

  @override
  Widget build(BuildContext context) {
    final label = TextPainter(
      text: TextSpan(
        text: 'M',
        style:
            ChipTheme.of(context).labelStyle ??
            Theme.of(context).textTheme.labelLarge,
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout();
    // Standard-density Material chips: 8dp vertical content padding on each
    // side, at least a 48dp target, plus the strip's two 4dp outer insets.
    final height = (label.height + 16).clamp(48.0, double.infinity) + 8;
    label.dispose();
    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        sliver: SliverList.builder(
          itemCount: widget.options.length,
          itemBuilder: (context, index) {
            final option = widget.options[index];
            return KeepBuilt(
              key: ValueKey(option),
              budget: _retained,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: ActionChip(
                    label: Text(option, maxLines: 1, softWrap: false),
                    onPressed: () => widget.onSelected(option),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
    return SizedBox(
      height: height,
      child: IdleBuildAhead(
        axis: Axis.horizontal,
        initialCache: 0,
        builder: (_, cache) => PixelCustomScrollView(
          scrollDirection: Axis.horizontal,
          scrollCacheExtent: ScrollCacheExtent.pixels(cache),
          slivers: slivers,
        ),
      ),
    );
  }
}

class _EditorField extends StatefulWidget {
  const _EditorField({
    super.key,
    required this.label,
    required this.readValue,
    required this.onChanged,
    this.multiline = false,
    this.timeField = false,
    this.compact = false,
    this.muted = false,
    this.semanticLabel,
    this.suggestions = const [],
    this.suggestionProvider,
    this.onSubmitted,
    this.onSelected,
    this.suffix,
    this.editingAction,
    this.aiLabel,
    this.hint,
    this.suggestionStrip = false,
    this.textCapitalization = TextCapitalization.none,
  });
  final TextCapitalization textCapitalization;
  final String label;
  // SliverList.list retains widget configurations after a field is recycled.
  // Read mutable draft text when the field mounts, never a captured snapshot.
  final String Function() readValue;
  String get value => readValue();
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted, onSelected;
  final bool multiline, timeField, compact, muted, suggestionStrip;
  final String? semanticLabel, aiLabel, hint;
  final List<String> suggestions;
  final List<String> Function()? suggestionProvider;
  final Widget? suffix, editingAction;
  @override
  State<_EditorField> createState() => _EditorFieldState();
}

class _EditorFieldState extends State<_EditorField> {
  Widget? _cachedField;
  bool _activated = false;
  final _idleText = GlobalKey();
  final _nativeField = GlobalKey();
  static int _nextActivationPointer = -1;
  PointerDownEvent? _activationDown;
  bool _initialLongPress = false;
  final _fieldScroll = PixelScrollController();
  late final TextEditingController _text = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  String _valueAtFocus = '';
  _EditorSuggestions? _suggestions;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _text.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cachedField = null;
    _suggestions = context
        .dependOnInheritedWidgetOfExactType<_EditorSuggestionsScope>()
        ?.suggestions;
    _activated =
        _activated ||
        _suggestions?.activatedFields.contains(widget.key) == true;
  }

  void _focusChanged() {
    if (_focus.hasFocus) _valueAtFocus = widget.value;
    final firstFocus = _focus.hasFocus && !_activated;
    if (mounted) {
      setState(() {
        if (_focus.hasFocus) {
          _activated = true;
          if (widget.key != null) {
            _suggestions?.activatedFields.add(widget.key!);
          }
        }
        _cachedField = null;
      });
    }
    if (firstFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focus.hasFocus) {
          _focus.context
              ?.findAncestorStateOfType<EditableTextState>()
              ?.requestKeyboard();
        }
      });
    }
    _refresh();
  }

  TextSelectionGestureDetector? _selectionDetector() {
    TextSelectionGestureDetector? detector;
    void findDetector(Element element) {
      if (element.widget is TextSelectionGestureDetector) {
        detector = element.widget as TextSelectionGestureDetector;
      } else if (detector == null) {
        element.visitChildElements(findDetector);
      }
    }

    (_nativeField.currentContext as Element?)?.visitChildElements(findDetector);
    return detector;
  }

  void _deliverInitialGesture(
    Offset point,
    PointerDeviceKind kind, {
    bool word = false,
  }) {
    if (!word) {
      // Give the native recognizers a complete first tap, not just selection
      // callbacks. Their own tap history then handles double-tap dragging,
      // movement slop, held presses and pointer cancellation normally.
      final binding = GestureBinding.instance;
      final hit = HitTestResult();
      final down = _activationDown;
      final viewId = View.of(context).viewId;
      binding.hitTestInView(hit, point, viewId);
      final pointer = _nextActivationPointer--;
      binding.dispatchEvent(
        PointerDownEvent(
          viewId: viewId,
          pointer: pointer,
          position: point,
          kind: kind,
          device: down?.device ?? 0,
          buttons: down?.buttons ?? kPrimaryButton,
        ),
        hit,
      );
      binding.dispatchEvent(
        PointerUpEvent(
          viewId: viewId,
          pointer: pointer,
          position: point,
          kind: kind,
          device: down?.device ?? 0,
        ),
        hit,
      );
      return;
    }
    final detector = _selectionDetector();
    final local =
        (_nativeField.currentContext?.findRenderObject() as RenderBox?)
            ?.globalToLocal(point) ??
        Offset.zero;
    final down = TapDragDownDetails(
      globalPosition: point,
      localPosition: local,
      kind: kind,
      consecutiveTapCount: 1,
    );
    // Hand the activating gesture to Material's own selection callbacks so
    // caret handles, word selection and platform-specific behavior match it.
    detector?.onTapDown?.call(down);
    if (word) {
      detector?.onSingleLongTapStart?.call(
        LongPressStartDetails(globalPosition: point, localPosition: local),
      );
    } else {
      detector?.onSingleTapUp?.call(
        TapDragUpDetails(
          globalPosition: point,
          localPosition: local,
          kind: kind,
          consecutiveTapCount: 1,
        ),
      );
    }
  }

  void _activate(
    Offset? point, {
    bool word = false,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) {
    _initialLongPress = word;
    if (!_activated) {
      final paragraph = _idleText.currentContext?.findRenderObject();
      final offset =
          point != null && paragraph is RenderParagraph && _text.text.isNotEmpty
          ? paragraph
                .getPositionForOffset(paragraph.globalToLocal(point))
                .offset
                .clamp(0, _text.text.length)
          : _text.text.length;
      _text.selection = TextSelection.collapsed(offset: offset);
      setState(() {
        _activated = true;
        if (widget.key != null) _suggestions?.activatedFields.add(widget.key!);
        _cachedField = null;
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      if (point != null) {
        _deliverInitialGesture(point, kind, word: word);
      }
    });
  }

  // Keep this recognizer mounted across activation: the pointer that began on
  // the lightweight row must continue a native long-press selection drag.
  // A resting field is already part of the editor's text-input region. Keep
  // the current native client attached until the new field can take focus;
  // otherwise the app's touch tap-outside action dismisses the IME on down.
  Widget _activationGestures(Widget child) => TextFieldTapRegion(
    child: Listener(
      onPointerDown: (event) {
        if (!_activated) _activationDown = event;
      },
      onPointerCancel: (_) => _initialLongPress = false,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          if (!_activated) {
            _activate(details.globalPosition, kind: details.kind);
          }
        },
        onLongPressStart: (details) {
          if (!_activated) _activate(details.globalPosition, word: true);
        },
        onLongPressMoveUpdate: (details) {
          if (_initialLongPress) {
            _selectionDetector()?.onSingleLongTapMoveUpdate?.call(details);
          }
        },
        onLongPressEnd: (details) {
          if (_initialLongPress) {
            _selectionDetector()?.onSingleLongTapEnd?.call(details);
            _initialLongPress = false;
          }
        },
        child: child,
      ),
    ),
  );

  void _refresh() {
    // Parent changes may update the text or options during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _suggestions?.refresh(this);
    });
  }

  void revealAboveSuggestions() {
    if (!mounted || !_focus.hasFocus || !widget.suggestionStrip) return;
    final box = _nativeField.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    // The strip can appear after the final IME metrics notification. Reveal
    // against the newly laid-out viewport without replacing the native field.
    box.showOnScreen(
      rect: Rect.fromLTWH(0, -8, box.size.width, box.size.height + 16),
    );
  }

  void select(String option) {
    _text.value = TextEditingValue(
      text: option,
      selection: TextSelection.collapsed(offset: option.length),
    );
    widget.onChanged(option);
    widget.onSelected?.call(option);
    _focus.requestFocus();
  }

  @override
  void didUpdateWidget(_EditorField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!_activated && widget.value != _text.text) ||
        widget.label != oldWidget.label ||
        widget.semanticLabel != oldWidget.semanticLabel ||
        widget.multiline != oldWidget.multiline ||
        widget.timeField != oldWidget.timeField ||
        widget.compact != oldWidget.compact ||
        widget.muted != oldWidget.muted ||
        widget.aiLabel != oldWidget.aiLabel ||
        widget.value.isEmpty != _text.text.isEmpty ||
        widget.suffix != oldWidget.suffix ||
        (widget.onSubmitted == null) != (oldWidget.onSubmitted == null) ||
        (_focus.hasFocus && widget.editingAction != oldWidget.editingAction)) {
      _cachedField = null;
    }
    if (_text.text != widget.value) {
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
    if (_focus.hasFocus) _refresh();
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _text.removeListener(_refresh);
    final suggestions = _suggestions;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => suggestions?.refresh(this),
    );
    _text.dispose();
    _focus.dispose();
    _fieldScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cachedField != null) return _cachedField!;
    final editing = _focus.hasFocus && widget.editingAction != null;
    final style = widget.muted
        ? Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
        : widget.compact
        ? Theme.of(context).textTheme.bodyMedium
        : Theme.of(context).textTheme.bodyLarge;
    double? timeHeight;
    if (widget.timeField) {
      final line = TextPainter(
        text: TextSpan(text: 'M', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      timeHeight = (line.height + 24).clamp(48.0, double.infinity);
      line.dispose();
    }
    final decoration = InputDecoration(
      isDense: widget.compact,
      maintainHintSize: !widget.compact,
      constraints: widget.timeField
          ? BoxConstraints.tightFor(height: timeHeight)
          : widget.compact
          ? const BoxConstraints(minHeight: 48)
          : null,
      contentPadding: widget.compact
          ? EdgeInsets.fromLTRB(8, 12, 8, editing ? 52 : 12)
          : null,
      labelText: widget.compact ? null : widget.label,
      floatingLabelBehavior: widget.timeField || widget.hint != null
          ? FloatingLabelBehavior.always
          : null,
      hintText: widget.hint ?? (widget.compact ? widget.label : null),
      hintMaxLines: widget.hint != null ? 4 : null,
      hintStyle: widget.compact
          ? Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : null,
      suffixIcon: widget.suffix,
      helperText: widget.aiLabel,
    );
    if (!_activated) {
      // Populated ingredient cells have no floating label, helper, suffix or
      // focused decoration. Rendering their resting outline directly avoids
      // mounting InputDecorator's animation/hint/layout subtree for every new
      // row during a fling. The actual field is unchanged on activation.
      final simpleResting =
          widget.compact &&
          widget.editingAction == null &&
          widget.aiLabel == null &&
          widget.suffix == null &&
          _text.text.isNotEmpty;
      final inputTheme = InputDecorationTheme.of(context);
      final enabledBorder =
          inputTheme.enabledBorder ??
          (inputTheme.border ?? const OutlineInputBorder()).copyWith(
            borderSide:
                WidgetStateProperty.resolveAs(
                  inputTheme.activeIndicatorBorder,
                  <WidgetState>{},
                ) ??
                BorderSide(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          );
      final restingText = Text(
        _text.text.isEmpty ? ' ' : _text.text,
        key: _idleText,
        style: style,
        maxLines: widget.multiline ? null : 1,
        // Single-line native fields lay out horizontally, even at spaces.
        softWrap: widget.multiline,
        overflow: TextOverflow.clip,
      );
      return _cachedField = _activationGestures(
        Semantics(
          label: widget.semanticLabel ?? widget.label,
          textField: true,
          value: _text.text,
          onTap: () => _activate(null),
          child: Focus(
            focusNode: _focus,
            child: simpleResting
                ? ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    // InputDecorator keeps its natural painted height at the
                    // top of the 48dp interaction box for short dense fields.
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: 1,
                      child: SizedBox(
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: inputTheme.fillColor,
                            shape: enabledBorder,
                          ),
                          child: Padding(
                            // Material 3 adds 4dp to each content inset; also
                            // reserve the native cursor's 3dp on the right.
                            padding: const EdgeInsets.fromLTRB(12, 12, 15, 12),
                            child: restingText,
                          ),
                        ),
                      ),
                    ),
                  )
                : InputDecorator(
                    decoration: decoration,
                    baseStyle: style,
                    isEmpty: _text.text.isEmpty,
                    // RenderEditable reserves 2dp for its cursor plus a 1dp gap.
                    // Match that width while idle so line wrapping never changes.
                    child: Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: restingText,
                    ),
                  ),
          ),
        ),
      );
    }
    // Once used, retain the native field and its undo/composing state for this
    // row's lifetime. Untouched rows never mount EditableText or an IME client.
    return _cachedField = _activationGestures(
      Semantics(
        label: widget.semanticLabel,
        child: TextFieldTapRegion(
          child: Stack(
            children: [
              TextField(
                key: _nativeField,
                controller: _text,
                scrollController: _fieldScroll,
                focusNode: _focus,
                autofocus: false,
                textCapitalization: widget.textCapitalization,
                autocorrect: true,
                enableSuggestions: true,
                minLines: 1,
                maxLines: widget.multiline ? null : 1,
                keyboardType: widget.multiline
                    ? TextInputType.multiline
                    : TextInputType.text,
                textInputAction: widget.multiline
                    ? TextInputAction.newline
                    : (widget.onSubmitted == null
                          ? TextInputAction.next
                          : TextInputAction.done),
                style: style,
                decoration: decoration,
                onChanged: (value) => widget.onChanged(value),
                onSubmitted: (value) => widget.onSubmitted?.call(_text.text),
              ),
              if (editing)
                Positioned(right: 0, bottom: 0, child: widget.editingAction!),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasteDialog extends StatefulWidget {
  const _PasteDialog({required this.controller, this.section});
  final EditorController controller;
  final EditableSection? section;
  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  EditorController get c => widget.controller;
  late final _text = TextEditingController(text: c.draft.pasteText);
  List<core.PastedIngredient>? _ingredients;
  List<String>? _steps, _amounts;
  String? _error;
  bool _busy = false;
  int _version = 0;
  bool get _isSteps => c.draft.pasteKind == 'steps';
  bool get _reviewed => _isSteps ? _steps != null : _ingredients != null;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    final version = ++_version;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_isSteps) {
        final steps = splitPastedSteps(_text.text);
        if (steps.isEmpty) {
          throw const FormatException('Paste at least one step.');
        }
        setState(() => _steps = steps);
      } else {
        final rows = await c.previewIngredients(
          _text.text,
          widget.section?.name ?? '',
        );
        final amounts = await c.store.repository.ingredientAmounts(
          rows.map((p) => p.ingredient).toList(),
        );
        if (!mounted || version != _version) return;
        if (rows.isEmpty) {
          throw const FormatException('Paste at least one ingredient.');
        }
        setState(() {
          _ingredients = rows;
          _amounts = amounts;
        });
      }
    } catch (e) {
      if (mounted && version == _version) {
        setState(
          () => _error = switch (e) {
            core.ServiceError() => e.message,
            FormatException() => e.message,
            _ => e.toString(),
          },
        );
      }
    } finally {
      if (mounted && version == _version) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      if (_isSteps) {
        c.applySteps(_steps!);
      } else {
        final target = widget.section;
        if (target == null || !c.draft.sections.contains(target)) {
          throw StateError('Choose an ingredient section first.');
        }
        await c.applyIngredients(_ingredients!, target);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is core.ServiceError ? e.message : e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      title: Text(_isSteps ? 'Paste steps' : 'Paste ingredients'),
      content: SizedBox(
        width: 520,
        child: PixelSingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PixelScrollScope(
                axis: Axis.horizontal,
                builder: (context) => DialogFieldPadding(
                  child: TextField(
                    scrollController: PrimaryScrollController.of(context),
                    controller: _text,
                    autofocus: false,
                    readOnly: _busy,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: _isSteps ? 'Steps' : 'Ingredients',
                    ),
                    textCapitalization: _isSteps
                        ? TextCapitalization.sentences
                        : TextCapitalization.none,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    onChanged: (value) {
                      c.draft.pasteText = value;
                      c.changed();
                      setState(() {
                        _version++;
                        _busy = false;
                        _ingredients = null;
                        _steps = null;
                        _error = null;
                      });
                    },
                  ),
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_steps != null)
                for (var i = 0; i < _steps!.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text('${i + 1}'),
                    title: Text(_steps![i]),
                  ),
              if (_ingredients != null)
                for (var i = 0; i < _ingredients!.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            _amounts![i],
                            _ingredients![i].ingredient.unit,
                            _ingredients![i].ingredient.name,
                          ].where((s) => s.isNotEmpty).join(' '),
                        ),
                        if (_ingredients![i].ingredient.section.isNotEmpty)
                          Text(
                            _ingredients![i].ingredient.section,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        if (_ingredients![i].ingredient.prepNote.isNotEmpty)
                          Text(_ingredients![i].ingredient.prepNote),
                        if (_ingredients![i].issue != null)
                          Text(
                            _ingredients![i].issue!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        const Divider(),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        if (c.draft.unappliedPaste)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _busy
                ? null
                : () {
                    c.clearPaste();
                    Navigator.pop(context);
                  },
            child: const Text('Discard'),
          ),
        TextButton(
          onPressed: _busy ? null : (_reviewed ? _apply : _review),
          child: Text(_reviewed ? 'Apply' : 'Review'),
        ),
      ],
    ),
  );
}
