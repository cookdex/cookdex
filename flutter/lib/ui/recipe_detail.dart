import 'dart:math' as math;

import 'recipe_scale_control.dart';
import 'pixel_scroll.dart';
import '../ingredient_display.dart';
import '../fraction_display.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../app_platform.dart' show webSourceUri;
import '../cook_controller.dart';
import '../recipe_store.dart';
import '../tag_labels.dart';
import '../src/rust/api.dart';
import 'components.dart';
import 'facelift_motion.dart';
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
    this.systemBottomInset = 0,
    this.onControlsHeight,
    this.backTooltip = 'Back to recipes',
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
  final double systemBottomInset;
  final ValueChanged<double>? onControlsHeight;
  final String backTooltip;

  @override
  State<RecipeDetail> createState() => _RecipeDetailState();
}

class _RecipeDetailState extends State<RecipeDetail>
    with TickerProviderStateMixin {
  Recipe? _recipe;
  List<String> _amounts = [];
  ScaledRecipeView? _scaled;
  bool _scaling = false;
  bool _loading = true;
  bool _failed = false;
  int _loadVersion = 0;
  final Map<int, GlobalKey> _stepKeys = {};
  final _ingredientsKey = GlobalKey();
  late final _controls = AnimationController(vsync: this);
  late final _entry = AnimationController(vsync: this)
    ..addListener(_moveEntryScroll);
  double _scrollStart = 0;
  GlobalKey? _entryTarget;
  double _entryStart = 0;
  int _motionGeneration = 0;
  int _lastStep = 0;
  double _controlsHeight = 100;
  bool _wasCooking = false;
  late final _readingOffsets = widget.store.preferences
      .openRecipeReadingOffsets(widget.recipeId);
  late final _scroll = PixelScrollController(
    initialScrollOffset: _readingOffsets['recipe'] ?? 0,
  );
  late final _overviewScroll = PixelScrollController(
    initialScrollOffset: _readingOffsets['overview'] ?? 0,
  );
  late final _directionsScroll = PixelScrollController(
    initialScrollOffset: _readingOffsets['directions'] ?? 0,
  );
  late final _panes = {
    'recipe': _scroll,
    'overview': _overviewScroll,
    'directions': _directionsScroll,
  };
  final GlobalKey _titleKey = GlobalKey();
  final _showBarTitle = ValueNotifier(false);

  void _saveReadingOffsets() {
    if (_wasCooking) return;
    for (final pane in _panes.entries) {
      if (pane.value.hasClients) _readingOffsets[pane.key] = pane.value.offset;
    }
    widget.store.preferences.saveRecipeReadingOffsets(
      widget.recipeId,
      _readingOffsets,
    );
  }

  @override
  void deactivate() {
    _saveReadingOffsets();
    super.deactivate();
  }

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
    if (cook.active != _wasCooking) {
      // Capture before the first cooking reveal. Keep cooking moves out of
      // the reading history until every pane has returned to its bookmark.
      if (cook.active) _saveReadingOffsets();
      _startEntryMotion();
      _wasCooking = cook.active;
    } else if (cook.active && cook.step != _lastStep) {
      _entryTarget = null;
      _revealStep();
    }
    _lastStep = cook.step;
  }

  void _startEntryMotion() {
    final entering = widget.cook.active;
    _motionGeneration++;
    _controls.duration = FaceliftMotion.duration(
      context,
      MotionGroup.cookEntry,
    );
    _entry.duration = FaceliftMotion.cookIngredientDuration(context);
    _entryStart = _entry.value;
    if (entering) {
      _entryTarget = widget.cook.resumedStepOnEntry
          ? _stepKeys[widget.cook.step]
          : _ingredientsKey;
      final target = _entryTarget?.currentContext;
      if (target != null) {
        _scrollStart = Scrollable.of(target).position.pixels;
      }
      _controls.forward();
      _entry.forward();
    } else {
      _entryTarget = null;
      for (final pane in _panes.entries) {
        final scroll = pane.value;
        if (!scroll.hasClients) continue;
        final reading = _readingOffsets[pane.key] ?? 0.0;
        final position = scroll.position;
        final target = reading.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (scroll.offset != target || position.isScrollingNotifier.value) {
          scroll.jumpTo(target);
        }
      }
      _controls.reverse();
      _entry.reverse();
    }
  }

  double get _ingredientProgress => Curves.easeInOut.transform(_entry.value);

  // The bar changes the viewport during entry. Resolve the target after
  // layout, and discard queued callbacks as soon as the user leaves Cook.
  void _moveEntryScroll() {
    if (_entryTarget == null) return;
    final generation = _motionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _motionGeneration) return;
      final target = _entryTarget?.currentContext;
      if (target == null) return;
      final box = target.findRenderObject();
      if (box == null || !box.attached) return;
      final position = Scrollable.of(target).position;
      final destination = RenderAbstractViewport.of(box)
          .getOffsetToReveal(box, _entryTarget == _ingredientsKey ? 0 : .25)
          .offset;
      final distance = 1 - _entryStart;
      final t = distance == 0
          ? 1.0
          : ((_entry.value - _entryStart) / distance).clamp(0.0, 1.0);
      final offset =
          (_scrollStart +
                  (destination - _scrollStart) * Curves.easeInOut.transform(t))
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (offset != position.pixels) position.jumpTo(offset);
    });
  }

  void _changed() {
    if (widget.store.cachedDetail(widget.recipeId) != _recipe) {
      _load();
    } else {
      setState(() {});
    }
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
    _controls.dispose();
    _entry.dispose();
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
    if (!mounted || !widget.cook.active) return;
    final context = _stepKeys[widget.cook.step]?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: FaceliftMotion.duration(context, MotionGroup.cook),
        curve: Curves.easeOutCubic,
        alignment: .25,
      );
    }
  });

  Future<void> _favorite() async {
    final recipe = _recipe;
    if (recipe == null) return;
    try {
      HapticFeedback.lightImpact();
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
  Widget build(BuildContext context) =>
      NotificationListener<ScrollEndNotification>(
        onNotification: (event) {
          if (event.depth == 0 && event.metrics.axis == Axis.vertical) {
            _saveReadingOffsets();
          }
          return false;
        },
        child: _content(context),
      );

  Widget _content(BuildContext context) => ListenableBuilder(
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
                      text: 'Cooking',
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
                  final showEdit =
                      theme.platform == TargetPlatform.windows ||
                      WindowSizeClass.of(context) != WindowSizeClass.compact;
                  final actionsWidth = buttonWidth + (showEdit ? 144 : 96);
                  final split = actionsWidth + 48 > constraints.maxWidth;
                  final back = IconButton(
                    tooltip: widget.backTooltip,
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
                              duration: FaceliftMotion.accessible(
                                context,
                                FaceliftMotion.titleFade,
                              ),
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
                        minimumSize: Size(buttonWidth, 36),
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
                    if (showEdit)
                      IconButton(
                        tooltip: 'Edit recipe',
                        onPressed: recipe == null ? null : widget.onEdit,
                        icon: const Icon(Symbols.edit),
                      ),
                    IconButton(
                      tooltip: widget.store.isFavorite(widget.recipeId)
                          ? 'Unfavorite recipe'
                          : 'Favorite recipe',
                      onPressed: recipe == null ? null : _favorite,
                      icon: FavoriteStar(
                        favorite: widget.store.isFavorite(widget.recipeId),
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
                : _cookPane(
                    PixelSingleChildScrollView(
                      key: PageStorageKey('recipe-${recipe.id}'),
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
          ),
        ],
      );
    },
  );

  double get _bottomSpaceHeight {
    final cooking = widget.showControls ? _controlsHeight + 16 : 32.0;
    final progress = Easing.emphasizedDecelerate.transform(_controls.value);
    return 32 + (cooking - 32) * progress;
  }

  Widget _bottomSpace() => AnimatedBuilder(
    animation: _controls,
    builder: (_, _) => SizedBox(height: _bottomSpaceHeight),
  );
  Widget _cookPane(Widget scroll, {Key? key}) => Stack(
    key: key,
    fit: StackFit.expand,
    children: [
      scroll,
      if (widget.showControls)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedBuilder(
            animation: _controls,
            builder: (context, child) {
              if (_controls.isDismissed) return const SizedBox.shrink();
              final progress = Easing.emphasizedDecelerate.transform(
                _controls.value,
              );
              return FractionalTranslation(
                translation: Offset(0, 1 - progress),
                child: IgnorePointer(
                  ignoring: !widget.cook.active,
                  child: ExcludeFocus(
                    excluding: !widget.cook.active,
                    child: child!,
                  ),
                ),
              );
            },
            child: MeasureHeight(
              onChanged: (height) {
                if (!mounted) return;
                if (_controlsHeight != height) {
                  setState(() => _controlsHeight = height);
                }
                widget.onControlsHeight?.call(height);
              },
              child: CookNavigation(
                cook: widget.cook,
                onRevealStep: _revealStep,
                systemBottomInset: widget.systemBottomInset,
              ),
            ),
          ),
        ),
    ],
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
                child: _cookPane(
                  Scrollbar(
                    controller: _directionsScroll,
                    child: PixelSingleChildScrollView(
                      key: PageStorageKey('recipe-directions-${recipe.id}'),
                      controller: _directionsScroll,
                      padding: const EdgeInsets.only(top: 12),
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
                  key: const Key('recipe-directions-pane'),
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
        key: _ingredientsKey,
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
        TweenAnimationBuilder<double>(
          tween: Tween(end: widget.cook.step.toDouble()),
          duration: FaceliftMotion.duration(context, MotionGroup.cook),
          curve: Curves.easeInOutCubic,
          builder: (context, position, child) => TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: widget.cook.active
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.primaryContainer.withValues(alpha: 0),
            ),
            duration: FaceliftMotion.duration(context, MotionGroup.cookEntry),
            curve: Curves.easeOutCubic,
            builder: (context, color, child) => _StepHighlight(
              position: position,
              color: color!,
              child: child!,
            ),
            child: child!,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < recipe.fields.steps.length; i++)
                _step(context, recipe.fields.steps[i], i),
            ],
          ),
        ),
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
        if (webSourceUri(recipe.fields.source) == null) ...[
          _heading(context, 'Source'),
          const SizedBox(height: 8),
          Text(recipe.fields.source),
        ] else
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
      _bottomSpace(),
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
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    ingredients[i].section,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: theme.textTheme.bodyMedium!.fontSize! + 2,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
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
                    ? () {
                        HapticFeedback.lightImpact();
                        widget.cook.toggleIngredient(i);
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      if (widget.cook.active || !_entry.isDismissed)
                        AnimatedBuilder(
                          animation: _entry,
                          builder: (context, child) {
                            final progress = _ingredientProgress;
                            if (progress == 0) return const SizedBox.shrink();
                            return SizedBox(
                              width: 36 * progress,
                              height: 0,
                              child: OverflowBox(
                                alignment: AlignmentDirectional.centerStart,
                                minWidth: 24,
                                maxWidth: 24,
                                minHeight: 24,
                                maxHeight: 24,
                                child: Opacity(
                                  opacity: progress,
                                  child: Transform.scale(
                                    alignment: AlignmentDirectional.centerStart,
                                    scale: progress,
                                    child: child,
                                  ),
                                ),
                              ),
                            );
                          },
                          child: Icon(
                            widget.cook.checkedIngredients.contains(i)
                                ? Symbols.check_circle
                                : Symbols.radio_button_unchecked,
                            fill: widget.cook.checkedIngredients.contains(i)
                                ? 1
                                : 0,
                            size: 24,
                          ),
                        ),
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
    final finished = widget.cook.active && index < widget.cook.step;
    final number = '${index + 1}';
    final numberStyle = theme.textTheme.labelMedium!;
    final numberSize = MediaQuery.textScalerOf(context)
        .scale(numberStyle.fontSize!);
    final badgeSize = math.max(
      28.0,
      12.0 +
          numberSize * math.max(numberStyle.height ?? 1.4, number.length * .75),
    );
    return Padding(
      key: _stepKeys.putIfAbsent(index, GlobalKey.new),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        selected: selected,
        button: widget.cook.active,
        label: 'Step ${index + 1}',
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.cook.active ? () => _selectStep(index) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: FaceliftMotion.duration(
                      context,
                      MotionGroup.cook,
                    ),
                    curve: Curves.easeInOutCubic,
                    width: badgeSize,
                    height: badgeSize,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: finished
                            ? theme.colorScheme.outlineVariant
                            : Colors.transparent,
                      ),
                      color: finished
                          ? Colors.transparent
                          : selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: FaceliftMotion.duration(
                        context,
                        MotionGroup.cook,
                      ),
                      curve: Curves.easeInOutCubic,
                      style: numberStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: finished
                            ? theme.colorScheme.onSurfaceVariant
                            : selected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                      ),
                      child: Text(number, textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      stepSpan(text),
                      style: TextStyle(
                        color: finished
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
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
}

// Paint against the actual row geometry so the highlight follows wrapped
// instructions, font changes, and resizing without measuring in another frame.
class _StepHighlight extends SingleChildRenderObjectWidget {
  const _StepHighlight({
    required this.position,
    required this.color,
    required super.child,
  });
  final double? position;
  final Color color;

  @override
  _RenderStepHighlight createRenderObject(BuildContext context) =>
      _RenderStepHighlight(position, color);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStepHighlight renderObject,
  ) => renderObject.update(position, color);
}

class _RenderStepHighlight extends RenderProxyBox {
  _RenderStepHighlight(this._position, this._color);
  double? _position;
  Color _color;

  void update(double? position, Color color) {
    if (_position == position && _color == color) return;
    _position = position;
    _color = color;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final rows = child! as RenderFlex;
    final index = _position?.clamp(0.0, (rows.childCount - 1).toDouble());
    if (index != null) {
      var row = rows.firstChild!;
      for (var i = 0; i < index.floor(); i++) {
        row = rows.childAfter(row)!;
      }
      Rect bounds(RenderBox box) {
        final top = (box.parentData! as FlexParentData).offset + offset;
        return Rect.fromLTWH(
          top.dx,
          top.dy + 2,
          box.size.width,
          box.size.height - 4,
        );
      }

      final rect = Rect.lerp(
        bounds(row),
        bounds(rows.childAfter(row) ?? row),
        index % 1,
      )!;
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..color = _color,
      );
    }
    super.paint(context, offset);
  }
}

class CookNavigation extends StatelessWidget {
  const CookNavigation({
    super.key,
    required this.cook,
    this.includeBottomInset = true,
    this.systemBottomInset = 0,
    this.onRevealStep,
  });
  final CookController cook;
  final bool includeBottomInset;
  final double systemBottomInset;
  final VoidCallback? onRevealStep;

  void _activate(VoidCallback action) {
    if (!cook.active) return;
    HapticFeedback.lightImpact();
    action();
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: _controlTextScaler(context)),
    child: ListenableBuilder(
      listenable: cook,
      builder: (context, _) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final background = theme.scaffoldBackgroundColor;
        final tablet = WindowSizeClass.of(context) != WindowSizeClass.compact;
        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        background.withValues(alpha: 0),
                        background.withValues(alpha: .92),
                        background,
                      ],
                      stops: const [0, .4, 1],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              bottom: includeBottomInset,
              minimum: EdgeInsets.only(
                bottom: includeBottomInset ? systemBottomInset : 0,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(8, 22, 8, tablet ? 24 : 16),
                child: Center(
                  heightFactor: 1,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: tablet ? 460 : 372),
                    child: Material(
                      key: const Key('cook-controls-card'),
                      color: colors.surfaceContainerHigh,
                      elevation: 3,
                      shadowColor: colors.shadow.withValues(alpha: .36),
                      shape: const StadiumBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (cook.wakeError != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text('Screen awake unavailable'),
                                    ),
                                    TextButton(
                                      onPressed: cook.retryWake,
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              ),
                            LayoutBuilder(
                              builder: (context, constraints) =>
                                  _buttons(context, constraints.maxWidth),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _buttons(BuildContext context, double width) {
    final theme = Theme.of(context);
    final stepLabel = 'Step ${cook.step + 1}';
    final countLabel = 'of ${cook.stepCount}';
    final hasNext = cook.step + 1 < cook.stepCount;
    final forward = hasNext ? 'Next' : 'Done';
    final style = theme.textTheme.labelLarge!.copyWith(fontSize: 16);
    final tablet = WindowSizeClass.of(context) != WindowSizeClass.compact;
    final counterStyle = theme.textTheme.labelLarge!.copyWith(
      fontSize: tablet ? 18 : 16,
    );
    final countStyle = theme.textTheme.labelSmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: tablet ? 15 : 12,
    );
    double textWidth(String label, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final result = painter.width.ceilToDouble();
      painter.dispose();
      return result;
    }

    final buttonWidth =
        math.max(textWidth('Back', style), textWidth(forward, style)) + 24;
    final counterWidth = math.max(
      textWidth(stepLabel, counterStyle),
      textWidth(countLabel, countStyle),
    );
    final inline = buttonWidth * 2 + counterWidth + 16 <= width;
    final middleWidth = math.min(
      math.max(tablet ? 128.0 : 104.0, counterWidth),
      math.max(counterWidth, width - buttonWidth * 2 - 16),
    );
    final arrows = (buttonWidth + 24) * 2 + middleWidth + 16 <= width;
    final stacked = 2 * buttonWidth + 8 > width;
    final label = InkWell(
      onTap: onRevealStep,
      borderRadius: BorderRadius.circular(28),
      child: Semantics(
        button: onRevealStep != null,
        liveRegion: true,
        key: const Key('cook-progress'),
        label: '$stepLabel $countLabel',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: tablet ? 60 : 54),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(stepLabel, textAlign: TextAlign.center, style: counterStyle),
              Text(countLabel, textAlign: TextAlign.center, style: countStyle),
            ],
          ),
        ),
      ),
    );
    final buttonStyle = FilledButton.styleFrom(
      shape: const StadiumBorder(),
      minimumSize: Size(0, tablet ? 60 : 54),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      textStyle: style,
    );
    Widget content(String text, bool back) => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (back && arrows) ...[
          const Icon(Symbols.arrow_back, size: 18),
          const SizedBox(width: 6),
        ],
        Text(
          text,
          key: back ? const Key('cook-previous-label') : null,
          maxLines: 1,
          softWrap: false,
        ),
        if (!back && arrows) ...[
          const SizedBox(width: 6),
          const Icon(Symbols.arrow_forward, size: 18),
        ],
      ],
    );
    final back = FilledButton.tonal(
      key: const Key('cook-previous'),
      style: buttonStyle.copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? null
              : theme.colorScheme.primaryContainer,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? null
              : theme.colorScheme.onPrimaryContainer,
        ),
      ),
      onPressed: cook.step > 0 ? () => _activate(cook.previous) : null,
      child: content('Back', true),
    );
    final next = FilledButton(
      style: buttonStyle,
      onPressed: () => _activate(hasNext ? cook.next : cook.toggle),
      child: content(forward, false),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!inline) ...[label, const SizedBox(height: 6)],
        if (stacked) ...[
          back,
          const SizedBox(height: 6),
          next,
        ] else
          Row(
            children: [
              Expanded(child: back),
              if (inline)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(width: middleWidth, child: label),
                )
              else
                const SizedBox(width: 8),
              Expanded(child: next),
            ],
          ),
      ],
    );
  }
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
          text: '${displayFractions(quantity)} ',
          semanticsLabel: '${spokenFractions(quantity)} ',
          style: amountDisplayStyle,
        ),
      TextSpan(text: ingredient.optional ? '$name (optional)' : name),
    ],
  );
}
