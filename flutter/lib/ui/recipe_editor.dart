import 'pixel_scroll.dart';

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
import '../src/rust/api.dart' as core;
import 'components.dart';
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
  });
  final EditorController controller;
  final List<String> tagSuggestions, ingredientSuggestions;
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor>
    with WidgetsBindingObserver {
  EditorController get c => widget.controller;
  EditorDraft get d => c.draft;
  bool _leaving = false, _backDialog = false;
  final _suggestions = _EditorSuggestions();
  final _keyboardVisible = ValueNotifier(false);
  List<String> _usedUnits = const [];
  final _hintWidths = <String, double>{};
  Timer? _unitTimer;
  late final List<String> _ingredientNames;
  late final List<String> _tags;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final summaries = c.store.summaries;
    List<String> grouped(bool tags) => groupNameSuggestions([
      for (final recipe in summaries)
        for (final name in tags ? recipe.tags : recipe.ingredients)
          NameObservation(
            name: name,
            recipeId: recipe.id,
            updatedAt: recipe.updatedAt,
          ),
    ]).map((suggestion) => suggestion.name).toList();
    _ingredientNames = summaries.isEmpty
        ? rankEditorSuggestions(
            summaries.isEmpty
                ? widget.ingredientSuggestions
                : summaries.expand((recipe) => recipe.ingredients),
          )
        : grouped(false);
    _tags = summaries.isEmpty
        ? rankEditorSuggestions(
            summaries.isEmpty
                ? widget.tagSuggestions
                : summaries.expand((recipe) => recipe.tags),
          )
        : grouped(true);
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
  }

  @override
  void dispose() {
    _unitTimer?.cancel();
    unawaited(c.flush());
    WidgetsBinding.instance.removeObserver(this);
    _keyboardVisible.dispose();
    _suggestions.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    _keyboardVisible.value = view.viewInsets.bottom > 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(c.flush());
  }

  Future<void> _back() async {
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

  Widget _heading(String text, {List<Widget> actions = const []}) => Padding(
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
  }) => Padding(
    key: ValueKey('field-$key'),
    padding: const EdgeInsets.only(bottom: 12),
    child: _EditorField(
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
    ),
  );

  Future<void> _rename(EditableSection section) async {
    final text = TextEditingController(text: section.name);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Section name'),
        content: PixelScrollScope(
          axis: Axis.horizontal,
          builder: (context) => TextField(
            scrollController: PrimaryScrollController.of(context),
            controller: text,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(ctx, text.text),
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
  }) => Padding(
    key: ValueKey(row.id),
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
    child: Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final phone = MediaQuery.sizeOf(context).width < 600;
            final sizedUnit = row.unit.trimLeft().startsWith('(');
            final amountWidth = _hintWidth(
              '1 1/2',
              minimum: _hintWidth('Amount', minimum: 80),
            ).clamp(0.0, constraints.maxWidth);
            // Reserve a complete package unit on phones before typing, so
            // activation does not resize the fields. Wider layouts retain
            // their compact units unless a package size needs this room.
            final unitWidth =
                (phone || sizedUnit
                        ? _hintWidth('(14 oz) cans') + 3
                        : _hintWidth('clove', minimum: 64))
                    .clamp(0.0, constraints.maxWidth);
            final nameWidth = _hintWidth(
              'Ingredient',
              minimum: unitWidth > 96 ? unitWidth + 1 : 96,
            );
            final wrapFields =
                amountWidth + unitWidth + nameWidth + 12 > constraints.maxWidth;
            final fieldWidgets = <Widget>[
              SizedBox(
                width: amountWidth,
                child: _compactField(
                  '${row.id}-amount',
                  'Amount',
                  () => row.amount,
                  (s) => row.amount = s,
                ),
              ),
              const SizedBox(width: 6),
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
                      (unit) =>
                          !_usedUnits.any((used) => used.toLowerCase() == unit),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (!wrapFields)
                Expanded(
                  child: _compactField(
                    '${row.id}-name',
                    'Ingredient',
                    () => row.name,
                    (s) => row.name = s,
                    multiline: true,
                    suggestions: _ingredientNames,
                  ),
                ),
            ];
            final fields = wrapFields
                ? Wrap(runSpacing: 6, children: fieldWidgets)
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: fieldWidgets,
                  );
            return wrapFields
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      fields,
                      const SizedBox(height: 6),
                      _compactField(
                        '${row.id}-name',
                        'Ingredient',
                        () => row.name,
                        (s) => row.name = s,
                        multiline: true,
                        suggestions: _ingredientNames,
                      ),
                    ],
                  )
                : fields;
          },
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
        LayoutBuilder(
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
                  _drag(dragIndex ?? index, 'Reorder ingredient ${index + 1}'),
                  const Spacer(),
                  SizedBox(
                    width: optionalWidth,
                    height: 48,
                    child: InkWell(
                      onTap: () => _change(() => row.optional = !row.optional),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Checkbox(
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              value: row.optional,
                              semanticLabel: 'Optional ingredient ${index + 1}',
                              onChanged: (value) =>
                                  _change(() => row.optional = value ?? false),
                            ),
                          ),
                          Text(
                            'Optional',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    tooltip: 'Delete ingredient ${index + 1}',
                    onPressed: () => _delete(section.rows, row, 'Ingredient'),
                    icon: Icon(
                      Symbols.delete,
                      color: Theme.of(context).colorScheme.error,
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
                      Align(alignment: Alignment.centerLeft, child: note),
                      controls,
                    ],
                  )
                : controls;
          },
        ),
        const Divider(),
      ],
    ),
  );

  Widget _sectionMenu(EditableSection section, int index) =>
      PopupMenuButton<String>(
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
              _delete(d.sections, section, 'Section');
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
          (flatIndex) => Material(
            key: ValueKey(section.id),
            color: section.name.isEmpty
                ? Colors.transparent
                : Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                const SizedBox(width: 12),
                if (section.name.isNotEmpty)
                  Expanded(
                    child: Text(
                      section.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (d.sections.length > 1)
                  _drag(flatIndex, 'Reorder section ${index + 1}'),
                _sectionMenu(section, index),
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
      entries.add((
        section,
        (_) => Padding(
          key: ValueKey('${section.id}-actions'),
          padding: const EdgeInsets.only(bottom: 12),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () =>
                    _change(() => section.rows.add(EditableIngredient())),
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
        null,
      ));
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
                color: Theme.of(context).colorScheme.error,
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
                appBar: AppBar(
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: c.saving ? null : _back,
                    icon: const Icon(Symbols.arrow_back),
                  ),
                  title: Text(
                    d.imported
                        ? 'Review import'
                        : d.base == null
                        ? 'Write a recipe'
                        : 'Edit recipe',
                  ),
                  actions: [
                    TextButton(
                      onPressed: c.saving ? null : _save,
                      child: Text(d.stale ? 'Save copy' : 'Save'),
                    ),
                  ],
                ),
                body: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Expanded(
                        child: AbsorbPointer(
                          absorbing: c.saving,
                          child: Builder(
                            builder: (context) {
                              final width = MediaQuery.sizeOf(context).width;
                              final inset = width > 792
                                  ? (width - 760) / 2
                                  : 16.0;
                              final entries = _ingredientEntries();
                              return _EditorScrollView(
                                // Retain Flutter's default look-ahead cache;
                                // zero cache increased field creation on flings.
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.manual,
                                slivers: [
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(
                                      inset,
                                      12,
                                      inset,
                                      0,
                                    ),
                                    sliver: SliverList.list(
                                      children: [
                                        if (c.saving)
                                          const LinearProgressIndicator(),
                                        if (d.imported)
                                          const Padding(
                                            padding: EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: Text(
                                              'Imported, review and save',
                                            ),
                                          ),
                                        for (final warning in d.importWarnings)
                                          Padding(
                                            padding: const EdgeInsets.only(
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
                                              padding: const EdgeInsets.only(
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
                                            padding: const EdgeInsets.only(
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
                                            margin: const EdgeInsets.fromLTRB(
                                              4,
                                              4,
                                              4,
                                              16,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Wrap(
                                                crossAxisAlignment:
                                                    WrapCrossAlignment.center,
                                                spacing: 8,
                                                children: [
                                                  const Text('Unapplied paste'),
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
                                                    child: const Text('Review'),
                                                  ),
                                                  TextButton(
                                                    style: TextButton.styleFrom(
                                                      foregroundColor: Theme.of(
                                                        context,
                                                      ).colorScheme.error,
                                                    ),
                                                    onPressed: c.clearPaste,
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
                                                    Directionality.of(context),
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
                                                ((constraints.maxWidth + 12) /
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
                                                    (s) => d.totalTime = s,
                                                    multiline: false,
                                                    timeField: true,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        if (d.aiGuessedFields.contains(
                                          'totalTime',
                                        ))
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 12,
                                            ),
                                            child: Text(
                                              'Total time: AI guess',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        _heading(
                                          'Tags',
                                          actions: [
                                            if (d.aiGuessedFields.contains(
                                              'tags',
                                            ))
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
                                            for (final tag in normalizeTags(
                                              d.tags,
                                            ))
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
                                          key: const ValueKey('tag-input'),
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
                                          actions: [
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextButton.icon(
                                                  onPressed: () {
                                                    final section =
                                                        EditableSection(
                                                          rows: [
                                                            EditableIngredient(),
                                                          ],
                                                        );
                                                    _change(
                                                      () => d.sections.add(
                                                        section,
                                                      ),
                                                    );
                                                    _rename(section);
                                                  },
                                                  icon: const Icon(Symbols.add),
                                                  label: const Text('Section'),
                                                ),
                                                if (d.sections.length == 1 &&
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
                                      onReorderStart: (_) =>
                                          HapticFeedback.lightImpact(),
                                      proxyDecorator: (
                                        child,
                                        index,
                                        animation,
                                      ) => Material(child: child),
                                      itemCount: entries.length,
                                      itemBuilder: (_, i) => entries[i].$2(i),
                                      onReorderItem: (a, b) =>
                                          _reorderIngredientEntries(
                                            entries,
                                            a,
                                            b,
                                          ),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: inset,
                                    ),
                                    sliver: SliverToBoxAdapter(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _heading(
                                            'Steps',
                                            actions: [
                                              TextButton.icon(
                                                onPressed: () =>
                                                    _paste('steps'),
                                                icon: const Icon(
                                                  Symbols.content_paste,
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
                                          _step(d.steps[i], i),
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
                                    sliver: SliverList.list(
                                      children: [
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                            onPressed: () => _change(
                                              () =>
                                                  d.steps.add(EditableStep('')),
                                            ),
                                            icon: const Icon(Symbols.add),
                                            label: const Text('Step'),
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
                                          'Source link',
                                          () => d.source,
                                          (s) => d.source = s,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: _keyboardVisible,
                        builder: (_, visible, _) => _EditorSuggestionStrip(
                          suggestions: _suggestions,
                          keyboardVisible: visible,
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

class _EditorScrollView extends PixelCustomScrollView {
  const _EditorScrollView({
    required super.slivers,
    super.keyboardDismissBehavior,
  });

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
    child: super.build(context),
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
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56),
            child: PixelSingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(option),
                        onPressed: () => field.select(option),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
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
                builder: (context) => TextField(
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
