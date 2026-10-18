import 'recipe_scale_control.dart';
import 'pixel_scroll.dart';
import '../ingredient_display.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../cook_controller.dart';
import '../recipe_store.dart';
import '../tag_labels.dart';
import '../src/rust/api.dart';
import 'components.dart';
import 'feedback.dart';
import 'recipe_metadata.dart';
import 'step_text.dart';
import 'window_size.dart';

class RecipeDetail extends StatefulWidget {
  const RecipeDetail({
    super.key,
    required this.store,
    required this.recipeId,
    required this.cook,
    required this.onBack,
    required this.onActions,
    required this.onEdit,
    required this.onSource,
    required this.onAddToShopping,
    this.showControls = true,
    this.onControlsHeight,
  });
  final RecipeStore store;
  final String recipeId;
  final CookController cook;
  final VoidCallback onBack;
  final VoidCallback onActions;
  final VoidCallback onEdit;
  final Future<void> Function(String) onSource;
  final VoidCallback onAddToShopping;
  final bool showControls;
  final ValueChanged<double>? onControlsHeight;

  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail> {
  Recipe? _recipe;
  List<String> _amounts = [];
  ScaledRecipeView? _scaled;
  bool _scaling = false;
  bool _loading = true;
  bool _failed = false;
  int _loadVersion = 0;
  final Map<int, GlobalKey> _stepKeys = {};
  int _lastStep = 0;
  bool _wasCooking = false;
  final ScrollController _scroll = PixelScrollController();
  final ScrollController _overviewScroll = PixelScrollController();
  final ScrollController _directionsScroll = PixelScrollController();
  final GlobalKey _titleKey = GlobalKey();
  final _showBarTitle = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    widget.cook.scale = 2;
    widget.store.addListener(_changed);
    widget.cook.addListener(_cookChanged);
    _scroll.addListener(_updateBarTitle);
    _overviewScroll.addListener(_updateBarTitle);
    _load();
  }

  void _updateBarTitle() {
    final title = _titleKey.currentContext?.findRenderObject();
    if (title is! RenderBox || !title.hasSize) return;
    final viewport = RenderAbstractViewport.maybeOf(title);
    if (viewport is! RenderBox) return;
    final show =
        title
            .localToGlobal(Offset(0, title.size.height), ancestor: viewport)
            .dy <=
        0;
    _showBarTitle.value = show;
  }

  void _cookChanged() {
    final cook = widget.cook;
    if (cook.active && (!_wasCooking || cook.step != _lastStep)) _revealStep();
    _lastStep = cook.step;
    _wasCooking = cook.active;
  }

  void _changed() {
    if (widget.store.cachedDetail(widget.recipeId) != _recipe) _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    try {
      final recipe = await widget.store.detail(widget.recipeId);
      final amounts = recipe == null
          ? <String>[]
          : await widget.store.ingredientAmounts(widget.recipeId);
      final scale = widget.cook.scale;
      final scaled = recipe != null && scale != 2
          ? await (widget.store.repository as ScalingRepository).scaleRecipe(
              recipe.fields,
              scale,
            )
          : null;
      if (!mounted || version != _loadVersion) return;
      if (scale != widget.cook.scale) {
        await _load();
        return;
      }
      widget.cook.setRecipe(recipe);
      setState(() {
        _recipe = recipe;
        _scaled = scaled;
        _amounts = amounts;
        _loading = false;
        _failed = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateBarTitle();
      });
    } catch (_) {
      if (mounted && version == _loadVersion) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _setScale(int scale) async {
    if (_scaling || _recipe == null) return;
    final recipe = _recipe!;
    setState(() => _scaling = true);
    try {
      final view = scale == 2
          ? null
          : await (widget.store.repository as ScalingRepository).scaleRecipe(
              recipe.fields,
              scale,
            );
      if (!mounted || _recipe != recipe) return;
      setState(() {
        widget.cook.scale = scale;
        _scaled = view;
      });
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Could not scale these amounts.',
          kind: FeedbackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _scaling = false);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    widget.cook.removeListener(_cookChanged);
    _scroll.dispose();
    _overviewScroll.dispose();
    _directionsScroll.dispose();
    _showBarTitle.dispose();
    super.dispose();
  }

  void _selectStep(int index) {
    widget.cook.selectStep(index);
  }

  void _revealStep() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final context = _stepKeys[widget.cook.step]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        alignment: .25,
      );
    }
  });

  Future<void> _favorite() async {
    final recipe = _recipe;
    if (recipe == null) return;
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.cook,
    builder: (context, _) {
      final recipe = _recipe;
      final theme = Theme.of(context);
      final cook = widget.cook;
      final expanded = WindowSizeClass.of(context) == WindowSizeClass.expanded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _updateBarTitle();
      });
      return Column(
        children: [
          MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: _controlTextScaler(context)),
            child: Material(
              color: theme.scaffoldBackgroundColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final label = TextPainter(
                    text: TextSpan(
                      text: cook.active ? 'Cooking' : 'Cook',
                      style: theme.textTheme.labelLarge,
                    ),
                    textDirection: Directionality.of(context),
                    textScaler: _controlTextScaler(context),
                  )..layout();
                  final buttonWidth = (label.width + 24).clamp(
                    64.0,
                    double.infinity,
                  );
                  label.dispose();
                  final actionsWidth = buttonWidth + 144;
                  final split = actionsWidth + 48 > constraints.maxWidth;
                  final back = IconButton(
                    tooltip: 'Back to recipes',
                    onPressed: widget.onBack,
                    icon: const Icon(Symbols.arrow_back),
                  );
                  final title = Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: _showBarTitle,
                      builder: (context, showBarTitle, child) =>
                          ExcludeSemantics(
                            excluding: !showBarTitle,
                            child: AnimatedOpacity(
                              opacity: showBarTitle ? 1 : 0,
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 150),
                              child: child,
                            ),
                          ),
                      child: Text(
                        recipe?.fields.title ?? '',
                        key: const Key('recipe-bar-title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  );
                  final actions = <Widget>[
                    TextButton(
                      key: const Key('cook-toggle'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(64, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        tapTargetSize: MaterialTapTargetSize.padded,
                        backgroundColor: cook.active
                            ? theme.colorScheme.primaryContainer
                            : Colors.transparent,
                      ),
                      onPressed: recipe == null || recipe.fields.steps.isEmpty
                          ? null
                          : cook.toggle,
                      child: Text(cook.active ? 'Cooking' : 'Cook'),
                    ),
                    IconButton(
                      tooltip: 'Edit recipe',
                      onPressed: recipe == null ? null : widget.onEdit,
                      icon: const Icon(Symbols.edit),
                    ),
                    IconButton(
                      tooltip: recipe?.favorite == true
                          ? 'Unfavorite recipe'
                          : 'Favorite recipe',
                      onPressed: recipe == null ? null : _favorite,
                      icon: Icon(
                        Symbols.star,
                        fill: recipe?.favorite == true ? 1 : 0,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Recipe actions',
                      onPressed: recipe == null ? null : widget.onActions,
                      icon: const Icon(Symbols.more_vert),
                    ),
                  ];
                  if (split) {
                    return Column(
                      key: const Key('recipe-toolbar'),
                      children: [
                        Row(children: [back, title]),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Wrap(children: actions),
                        ),
                      ],
                    );
                  }
                  return Row(
                    key: const Key('recipe-toolbar'),
                    children: [back, title, ...actions],
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                ? Center(
                    child: PixelSingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Could not load recipe',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : recipe == null
                ? const Center(
                    child: PixelSingleChildScrollView(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Recipe no longer available',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : expanded
                ? _expandedContent(context, recipe)
                : PixelSingleChildScrollView(
                    key: PageStorageKey('recipe-${recipe.id}'),
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: RepaintBoundary(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 850),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              ..._overview(context, recipe),
                              ..._directions(context, recipe),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          if (!expanded && cook.active && widget.showControls)
            CookNavigation(cook: cook),
        ],
      );
    },
  );

  Widget _expandedContent(BuildContext context, Recipe recipe) => LayoutBuilder(
    builder: (context, constraints) {
      const gutter = 24.0;
      final availableWidth = constraints.maxWidth - 32;
      final overviewWidth = (availableWidth - gutter - 300).clamp(300.0, 420.0);
      final directionsWidth = (availableWidth - overviewWidth - gutter).clamp(
        0.0,
        _readableWidth(context),
      );
      return Center(
        child: SizedBox(
          width: overviewWidth + gutter + directionsWidth,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const Key('recipe-overview-pane'),
                width: overviewWidth,
                child: Scrollbar(
                  controller: _overviewScroll,
                  child: PixelSingleChildScrollView(
                    key: PageStorageKey('recipe-overview-${recipe.id}'),
                    controller: _overviewScroll,
                    padding: const EdgeInsets.only(top: 12, bottom: 32),
                    child: RepaintBoundary(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _overview(context, recipe),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: gutter),
              SizedBox(
                width: directionsWidth,
                child: Column(
                  key: const Key('recipe-directions-pane'),
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: _directionsScroll,
                        child: PixelSingleChildScrollView(
                          key: PageStorageKey('recipe-directions-${recipe.id}'),
                          controller: _directionsScroll,
                          padding: const EdgeInsets.only(top: 12, bottom: 32),
                          child: RepaintBoundary(
                            child: SizedBox(
                              key: const Key('recipe-readable-directions'),
                              width: directionsWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _directions(
                                  context,
                                  recipe,
                                  expanded: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.cook.active && widget.showControls)
                      MeasureHeight(
                        onChanged: (height) =>
                            widget.onControlsHeight?.call(height),
                        child: CookNavigation(cook: widget.cook),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  // Approximate a 90-character line using the displayed body font and scaler.
  // On narrower expanded windows the pane naturally supplies a shorter line.
  double _readableWidth(BuildContext context) {
    final measure = TextPainter(
      text: TextSpan(
        text: 'Mix the ingredients gently until combined, then cook over a medium heat until just tender.  ',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = measure.width;
    measure.dispose();
    // Step badges and spacing consume 56dp before their flowing body text.
    return width + 56;
  }

  List<Widget> _overview(BuildContext context, Recipe recipe) {
    final theme = Theme.of(context);
    return [
      Text(
        recipe.fields.title,
        key: _titleKey,
        style: theme.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
      if (recipe.fields.description.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(recipe.fields.description),
        ),
      if (!_metadata(recipe.fields, servings: _scaled?.servings).isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _metadata(recipe.fields, servings: _scaled?.servings),
        ),
      if (recipe.fields.tags.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in normalizeTags(recipe.fields.tags))
                TonalTag(tag),
            ],
          ),
        ),
      const SizedBox(height: 24),
      RecipeScaleControl(
        scale: widget.cook.scale,
        enabled: !_scaling,
        onSelected: _setScale,
        heading: _heading(context, 'Ingredients'),
        textScaler: _controlTextScaler(context),
      ),
      const SizedBox(height: 12),
      _ingredients(context, recipe),
    ];
  }

  List<Widget> _directions(
    BuildContext context,
    Recipe recipe, {
    bool expanded = false,
  }) {
    final theme = Theme.of(context);
    return [
      if (recipe.fields.steps.isNotEmpty) ...[
        if (!expanded) const SizedBox(height: 24),
        _heading(context, 'Steps'),
        if (widget.cook.scale != 2)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text("Amounts in steps aren't scaled."),
          ),
        const SizedBox(height: 8),
        for (var i = 0; i < recipe.fields.steps.length; i++)
          _step(context, recipe.fields.steps[i], i),
      ],
      if (recipe.fields.notes.isNotEmpty) ...[
        const SizedBox(height: 24),
        _heading(context, 'Notes'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(recipe.fields.notes),
        ),
      ],
      if (recipe.fields.source.isNotEmpty) ...[
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              try {
                await widget.onSource(recipe.fields.source);
              } catch (_) {
                if (context.mounted) {
                  showFeedback(
                    context,
                    'Could not open source',
                    kind: FeedbackKind.error,
                  );
                }
              }
            },
            icon: const Icon(Symbols.open_in_new),
            label: Text(recipe.fields.source, softWrap: true),
          ),
        ),
      ],
    ];
  }

  Widget _ingredients(BuildContext context, Recipe recipe) {
    final theme = Theme.of(context);
    final ingredients = recipe.fields.ingredients;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < ingredients.length; i++) ...[
            if (ingredients[i].section.isNotEmpty &&
                (i == 0 ||
                    ingredients[i].section != ingredients[i - 1].section))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    ingredients[i].section,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (i > 0 && ingredients[i].section == ingredients[i - 1].section)
              const Divider(height: 1, indent: 16, endIndent: 16),
            Semantics(
              checked: widget.cook.active
                  ? widget.cook.checkedIngredients.contains(i)
                  : null,
              child: InkWell(
                onTap: widget.cook.active
                    ? () => widget.cook.toggleIngredient(i)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (widget.cook.active) ...[
                        Icon(
                          widget.cook.checkedIngredients.contains(i)
                              ? Symbols.check_circle
                              : Symbols.radio_button_unchecked,
                          fill: widget.cook.checkedIngredients.contains(i)
                              ? 1
                              : 0,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              _ingredientLabel(
                                ingredients[i],
                                _scaled?.quantities[i] ??
                                    (i < _amounts.length ? _amounts[i] : ''),
                                includeUnit: _scaled == null,
                              ),
                              style: TextStyle(
                                decoration:
                                    widget.cook.active &&
                                        widget.cook.checkedIngredients.contains(
                                          i,
                                        )
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (ingredients[i].prepNote.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  ingredients[i].prepNote,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextButton.icon(
              onPressed: widget.onAddToShopping,
              icon: const Icon(Symbols.playlist_add),
              label: const Text('Add to shopping list'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, String text, int index) {
    final theme = Theme.of(context);
    final selected = widget.cook.active && widget.cook.step == index;
    return Padding(
      key: _stepKeys.putIfAbsent(index, GlobalKey.new),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: widget.cook.active,
        label: 'Step ${index + 1}',
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.cook.active ? () => _selectStep(index) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text.rich(stepSpan(text))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned below the recipe scroll view, or below the expanded directions pane.
class CookNavigation extends StatelessWidget {
  const CookNavigation({
    super.key,
    required this.cook,
    this.includeBottomInset = true,
  });
  final CookController cook;
  // The shell's compact navigation bar can own the gesture inset below this.
  final bool includeBottomInset;

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: _controlTextScaler(context)),
    child: ListenableBuilder(
      listenable: cook,
      builder: (context, _) => SafeArea(
        top: false,
        bottom: includeBottomInset,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Material(
            key: const Key('cook-controls-card'),
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (cook.wakeError != null)
                    Row(
                      children: [
                        const Expanded(child: Text('Screen awake unavailable')),
                        TextButton(
                          onPressed: cook.retryWake,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final theme = Theme.of(context);
                      final buttonText = theme.textTheme.labelLarge?.copyWith(
                        fontSize: 16,
                      );
                      final progressText = theme.textTheme.bodyMedium;
                      final progress =
                          'Step ${cook.step + 1} of ${cook.stepCount}';
                      final shortProgress =
                          '${cook.step + 1}/${cook.stepCount}';
                      final forward = cook.canNext ? 'Next' : 'Done';
                      double textWidth(String text, TextStyle? style) {
                        final measure = TextPainter(
                          text: TextSpan(text: text, style: style),
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout();
                        final width = measure.width;
                        measure.dispose();
                        return width;
                      }

                      // Reserve each button's actual label width: equal widths
                      // would wrap Previous long before Next needs the space.
                      var previousLabel = 'Previous';
                      var previousArrow = true;
                      var previousWidth =
                          textWidth('Previous', buttonText) + 56;
                      if (previousWidth > constraints.maxWidth) {
                        previousArrow = false;
                        previousWidth =
                            textWidth(previousLabel, buttonText) + 24;
                        if (previousWidth > constraints.maxWidth) {
                          previousLabel = 'Prev';
                          previousWidth =
                              textWidth(previousLabel, buttonText) + 24;
                        }
                      }
                      final forwardWidth = textWidth(forward, buttonText) + 56;
                      final buttonsWidth = previousWidth + forwardWidth;
                      final fullInline =
                          buttonsWidth +
                              textWidth(progress, progressText) +
                              16 <=
                          constraints.maxWidth;
                      final label = fullInline ? progress : shortProgress;
                      final progressWidth = textWidth(label, progressText);
                      final inline =
                          buttonsWidth + progressWidth + 16 <=
                          constraints.maxWidth;
                      final stackButtons =
                          buttonsWidth + 8 > constraints.maxWidth;
                      final progressLabel = Semantics(
                        liveRegion: true,
                        label: progress,
                        child: ExcludeSemantics(
                          child: Text(
                            label,
                            key: const Key('cook-progress'),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            softWrap: false,
                            style: progressText,
                          ),
                        ),
                      );
                      final style = ButtonStyle(
                        minimumSize: const WidgetStatePropertyAll(Size(0, 56)),
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        textStyle: WidgetStatePropertyAll(buttonText),
                      );
                      Widget buttonLabel(
                        String text,
                        IconData icon,
                        bool back, {
                        bool showArrow = true,
                        Key? labelKey,
                      }) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (back && showArrow) ...[
                            Icon(icon),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            text,
                            key: labelKey,
                            maxLines: 1,
                            softWrap: false,
                          ),
                          if (!back && showArrow) ...[
                            const SizedBox(width: 8),
                            Icon(icon),
                          ],
                        ],
                      );
                      final previous = OutlinedButton(
                        key: const Key('cook-previous'),
                        onPressed: cook.canPrevious ? cook.previous : null,
                        style: style,
                        child: Semantics(
                          label: 'Previous step',
                          child: ExcludeSemantics(
                            child: buttonLabel(
                              previousLabel,
                              Symbols.arrow_back,
                              true,
                              showArrow: previousArrow,
                              labelKey: const Key('cook-previous-label'),
                            ),
                          ),
                        ),
                      );
                      final next = FilledButton(
                        onPressed: !cook.active
                            ? null
                            : cook.canNext
                            ? cook.next
                            : cook.toggle,
                        style: style,
                        child: buttonLabel(
                          forward,
                          Symbols.arrow_forward,
                          false,
                        ),
                      );
                      // Respect system text sizing even on narrow phones. The
                      // counter shortens first; extreme sizes use two button
                      // rows, preserving their labels and touch targets.
                      final spare =
                          (constraints.maxWidth -
                              buttonsWidth -
                              (inline ? progressWidth + 16 : 8)) /
                          2;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!inline) ...[
                            progressLabel,
                            const SizedBox(height: 8),
                          ],
                          if (stackButtons) ...[
                            previous,
                            const SizedBox(height: 8),
                            next,
                          ] else
                            Row(
                              children: [
                                SizedBox(
                                  width: previousWidth + spare,
                                  child: previous,
                                ),
                                if (inline)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: progressLabel,
                                  )
                                else
                                  const SizedBox(width: 8),
                                SizedBox(
                                  width: forwardWidth + spare,
                                  child: next,
                                ),
                              ],
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

// Recipe reading size is composed with the system scaler at the shell. Controls
// retain system accessibility scaling without the additional recipe preference.
TextScaler _controlTextScaler(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return scaler is RecipeTextScaler ? scaler.system : scaler;
}

Widget _heading(BuildContext context, String text) => Text(
  text,
  style: Theme.of(context).textTheme.titleLarge
      ?.copyWith(fontWeight: FontWeight.w800),
);

RecipeMetadata _metadata(RecipeFields fields, {String? servings}) =>
    RecipeMetadata(
      servings: servings ?? fields.servings,
      totalTime: fields.totalTime,
      prepTime: fields.prepTime,
      cookTime: fields.cookTime,
      showAllTimes: true,
    );

TextSpan _ingredientLabel(
  Ingredient ingredient,
  String amount, {
  bool includeUnit = true,
}) {
  final name = ingredient.amount is Amount_ToTaste
      ? '${ingredient.name}, to taste'
      : ingredient.name;
  final quantity = ingredient.amount is Amount_ToTaste
      ? ''
      : [
          amount,
          if (includeUnit) displayIngredientUnit(ingredient),
        ].where((value) => value.isNotEmpty).join(' ');
  return TextSpan(
    style: const TextStyle(fontWeight: FontWeight.w400),
    children: [
      if (quantity.isNotEmpty)
        TextSpan(
          text: '$quantity ',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      TextSpan(text: ingredient.optional ? '$name (optional)' : name),
    ],
  );
}
