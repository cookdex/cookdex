part of 'smart_create_screen.dart';

extension _SmartCreateIdeas on _SmartCreateScreenState {
  List<Widget> _ideas() {
    final batch = c.arrivingIdeas ?? c.ideas;
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              [
                if (!c.moodOnly) 'From $_ingredientCount',
                if (!c.moodOnly && c.useFirst.isNotEmpty)
                  '${c.useFirst.length} to use up',
                if (c.mood.trim().isNotEmpty)
                  'In the mood for ${c.mood.trim()}',
              ].join(' · '),
              style: FaceliftTokens.tileSubtitle(context),
            ),
          ),
          TextButton(
            onPressed: () {
              _retry = null;
              if (_busy) c.cancel();
              c.edit();
            },
            child: const Text('Edit'),
          ),
        ],
      ),
      _IdeaBatch(
        key: const ValueKey('idea-batch'),
        message: c.error == null || _writingTitle == null
            ? _message()
            : const SizedBox.shrink(),
        batch: batch,
        replacing: c.progressAction == 'more' && c.arrivingIdeas == null,
        preview: c.arrivingIdeas != null,
        children: [
          for (final group in [
            if (c.moodOnly)
              (null, batch)
            else ...[
              ('Ready to make', batch.where((idea) => idea.missing.isEmpty)),
              (
                'Need a few things',
                batch.where((idea) => idea.missing.isNotEmpty),
              ),
            ],
          ])
            if (group.$2.isNotEmpty) ...[
              if (group.$1 case final String title)
                (
                  card: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      title,
                      style: FaceliftTokens.categoryTitle(context),
                    ),
                  ),
                ),
              for (final idea in group.$2)
                (
                  card: true,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _ideaCard(idea),
                  ),
                ),
            ],
        ],
      ),
    ];
  }

  Widget _newIdeasButton() => _smart(
    'more',
    'New ideas',
    () => _run(() {
      _writingTitle = null;
      if (_ideasScroll.hasClients) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _ideasScroll.jumpTo(0);
        } else {
          _ideasScroll.animateTo(
            0,
            duration: const Duration(milliseconds: 420),
            curve: const _CreateScrollCurve(),
          );
        }
      }
      return c.getIdeas(more: true);
    }),
    outlined: true,
  );

  Widget _ideaCard(CreateIdea idea) {
    final open = _openIdea == idea.title;
    final writing = _writingTitle == idea.title && c.progressAction == 'recipe';
    final canToggle = c.progressAction != 'more';
    final key = _ideaKeys.putIfAbsent(idea.title, GlobalKey.new);
    return KeyedSubtree(
      key: key,
      child: _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              enabled: canToggle,
              expanded: open,
              child: _DisclosureHeader(
                onTap: !canToggle
                    ? null
                    : () {
                        _update(() => _openIdea = open ? null : idea.title);
                      },
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 14, 14, open ? 8 : 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              idea.title,
                              style: FaceliftTokens.tileTitle(context),
                            ),
                          ),
                          AnimatedRotation(
                            turns: open ? .5 : 0,
                            duration: _createDuration(
                              context,
                              open ? 242 : 220,
                            ),
                            child: Icon(
                              Symbols.expand_more,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        idea.pitch,
                        maxLines: open ? null : 3,
                        overflow: open ? null : TextOverflow.ellipsis,
                        style: FaceliftTokens.tileSubtitle(context),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _tag(
                            '${idea.effort} · ${idea.minutes} min',
                            leading: CreateEffortBars(switch (idea.effort
                                .toLowerCase()) {
                              'easy' => 1,
                              'medium' => 2,
                              _ => 3,
                            }, colors.primary),
                          ),
                          if (idea.caloriesPerServing case final int calories)
                            Semantics(
                              label: 'About $calories calories per serving',
                              excludeSemantics: true,
                              child: _tag(
                                open
                                    ? '~$calories cal per serving'
                                    : '~$calories cal',
                              ),
                            ),
                          if (c.savedRecipes.containsKey(idea.title))
                            TweenAnimationBuilder<double>(
                              duration: _createDuration(context, 500),
                              curve: const Interval(
                                .52,
                                1,
                                curve: Curves.easeOut,
                              ),
                              tween: Tween(begin: 0, end: 1),
                              builder: (_, t, child) => Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale: .7 + .3 * t,
                                  child: child,
                                ),
                              ),
                              child: _tag(
                                'Saved',
                                leading: const Icon(Symbols.check),
                              ),
                            ),
                        ],
                      ),
                      if (!open && (c.moodOnly || idea.missing.isNotEmpty)) ...[
                        const SizedBox(height: 6),
                        _detailLine(
                          Symbols.shopping_cart,
                          idea.missing.isEmpty
                              ? 'Uses only your staples'
                              : "Need: ${idea.missing.join(', ')}",
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            _CreateDisclosure(
              open: open || writing,
              sectionKey: key,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!writing || open) ...[
                      if (idea.dietaryChips.isNotEmpty) ...[
                        Text(
                          idea.dietaryChips.take(3).join(' · '),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        idea.effortNote,
                        style: FaceliftTokens.tileSubtitle(context),
                      ),
                      if (!c.moodOnly) ...[
                        if (idea.have.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text('You have', style: theme.textTheme.labelLarge),
                          const SizedBox(height: 4),
                          _ownedIngredients(idea.have),
                        ],
                        if (idea.staples.isNotEmpty) _staplesLine(idea),
                      ],
                      if (idea.missing.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('You’ll need', style: theme.textTheme.labelLarge),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 5,
                          runSpacing: 5,
                          children: [
                            for (final name in idea.missing)
                              _tag(
                                name,
                                leading: const Icon(Symbols.add),
                                missing: true,
                              ),
                          ],
                        ),
                      ],
                      if (c.moodOnly && idea.staples.isNotEmpty)
                        _staplesLine(idea),
                      const SizedBox(height: 12),
                    ],
                    KeyedSubtree(
                      key: const ValueKey('idea-actions'),
                      child: _ideaActions(idea),
                    ),
                    if (_shoppingErrorTitle == idea.title)
                      Padding(
                        key: _shoppingErrorKey,
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            'Could not add these ingredients to the shopping list.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ),
                      ),
                    if (_writingTitle == idea.title && c.error != null)
                      _message(),
                  ],
                ),
              ),
            ),
          ],
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _ideaActions(CreateIdea idea) {
    final saved = c.savedRecipes[idea.title];
    final added = c.addedToList.contains(idea.title);
    final addLabel = added
        ? 'Added to list'
        : 'Add ${idea.missing.length} to list';
    final writing = c.progressAction == 'recipe' && _writingTitle == idea.title;
    final recipeButton = saved != null
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: _createDuration(context, 420),
            curve: const Interval(200 / 420, 1, curve: Curves.easeOut),
            builder: (_, value, child) => Opacity(opacity: value, child: child),
            child: FilledButton.tonalIcon(
              onPressed: widget.onViewRecipe == null
                  ? null
                  : () => widget.onViewRecipe!(saved),
              icon: const Icon(Symbols.menu_book),
              label: const Text('Open recipe'),
            ),
          )
        : SmartActionButton(
            controller: writing ? _working['recipe'] : null,
            label: 'Get the recipe',
            phase: writing ? c.progress : null,
            onCancel: () {
              _retry = null;
              c.cancel();
            },
            onPressed: _busy ? null : () => _run(() => _review(idea)),
          );
    if (idea.missing.isEmpty) {
      return SizedBox(width: double.infinity, child: recipeButton);
    }
    final addButton = ExcludeFocus(
      excluding: writing,
      child: ExcludeSemantics(
        excluding: writing,
        child: IgnorePointer(
          ignoring: writing,
          child: AnimatedOpacity(
            duration: _createDuration(context, 200),
            opacity: writing ? 0 : 1,
            child: Semantics(
              liveRegion: added,
              excludeSemantics: added,
              label: added ? addLabel : null,
              button: added ? true : null,
              enabled: added ? false : null,
              child: OutlinedButton.icon(
                style: added
                    ? OutlinedButton.styleFrom(
                        disabledForegroundColor: colors.onSurfaceVariant,
                        disabledIconColor: colors.onSurfaceVariant,
                      )
                    : null,
                onPressed: c.progressAction == 'more' || _addingToList || added
                    ? null
                    : () => _shop(idea),
                icon: Icon(
                  added ? Symbols.check : Symbols.add_shopping_cart,
                  size: 17,
                ),
                label: Text(addLabel, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = theme.textTheme.labelLarge;
        double measure(String text) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width;
        }

        final half = (constraints.maxWidth - 8) / 2;
        final stacked =
            half < measure(addLabel) + 60 ||
            half <
                measure(saved == null ? 'Get the recipe' : 'Open recipe') + 60;
        return TweenAnimationBuilder<double>(
          duration: _createDuration(context, 340),
          curve: Curves.ease,
          tween: Tween(end: writing ? 0 : 1),
          child: addButton,
          builder: (_, t, shopping) {
            if (stacked) {
              return _StackedIdeaActions(
                fraction: t,
                shopping: shopping!,
                recipe: recipeButton,
              );
            }
            return Row(
              children: [
                SizedBox(
                  width: half * t,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: half,
                      maxWidth: half,
                      fit: OverflowBoxFit.deferToChild,
                      child: shopping,
                    ),
                  ),
                ),
                SizedBox(width: 8 * t),
                Expanded(child: recipeButton),
              ],
            );
          },
        );
      },
    );
  }

  Widget _ownedIngredients(List<String> names) {
    final selected = c.useFirst.map((name) => name.toLowerCase()).toSet();
    final first = <String>[], rest = <String>[];
    for (final name in names) {
      (selected.contains(name.toLowerCase()) ? first : rest).add(name);
    }
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, name) in first.indexed) ...[
            if (i > 0) const TextSpan(text: ', '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 3),
                child: Icon(Symbols.timer, size: 15, color: colors.primary),
              ),
            ),
            // Keep the timer with the start of its ingredient when wrapping.
            TextSpan(
              text: '\u2060$name',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if (first.isNotEmpty && rest.isNotEmpty) const TextSpan(text: ', '),
          TextSpan(text: rest.join(', ')),
        ],
      ),
      style: theme.textTheme.bodyMedium,
      semanticsLabel: [
        for (final name in first) '$name (use first)',
        ...rest,
      ].join(', '),
    );
  }

  Widget _staplesLine(CreateIdea idea) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      "Staples: ${idea.staples.join(', ')}",
      style: theme.textTheme.bodySmall,
    ),
  );

  Widget _detailLine(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 17, color: colors.primary),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
    ],
  );

  Widget _tag(String text, {Widget? leading, bool missing = false}) =>
      CustomPaint(
        foregroundPainter: missing ? _DashedOutline(colors.outline) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: missing ? null : colors.secondaryContainer,
            borderRadius: BorderRadius.circular(FaceliftTokens.tagRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(size: 15, color: colors.primary),
                    child: leading,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(child: Text(text, style: theme.textTheme.labelMedium)),
              ],
            ),
          ),
        ),
      );
}

class _StackedIdeaActions extends StatefulWidget {
  const _StackedIdeaActions({
    required this.fraction,
    required this.shopping,
    required this.recipe,
  });
  final double fraction;
  final Widget shopping, recipe;

  @override
  State<_StackedIdeaActions> createState() => _StackedIdeaActionsState();
}

class _StackedIdeaActionsState extends State<_StackedIdeaActions> {
  bool _following = false;

  @override
  void didUpdateWidget(_StackedIdeaActions previous) {
    super.didUpdateWidget(previous);
    if (widget.fraction <= previous.fraction) return;
    final scroll = Scrollable.of(context).position;
    final target = context.findRenderObject() as RenderBox?;
    if (target == null || !target.attached || !scroll.hasContentDimensions) {
      return;
    }
    final viewport = RenderAbstractViewport.of(target);
    if (previous.fraction == 0) {
      final bottom = viewport.getOffsetToReveal(target, 1).offset;
      _following =
          bottom - scroll.pixels < target.size.height &&
          bottom + scroll.viewportDimension > scroll.pixels;
    }
    if (!_following) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !target.attached || !scroll.hasContentDimensions) return;
      if (scroll.isScrollingNotifier.value) {
        _following = false;
        return;
      }
      final bottom = viewport.getOffsetToReveal(target, 1).offset + 8;
      final offset = bottom.clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      );
      if (offset > scroll.pixels + .5) scroll.jumpTo(offset);
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: widget.fraction,
          child: SizedBox(width: double.infinity, child: widget.shopping),
        ),
      ),
      SizedBox(height: 8 * widget.fraction),
      widget.recipe,
    ],
  );
}

enum _BatchPhase { idle, leaving, waiting, arriving, restoring }

class _IdeaBatch extends StatefulWidget {
  const _IdeaBatch({
    super.key,
    required this.message,
    required this.batch,
    required this.replacing,
    required this.preview,
    required this.children,
  });

  final List<CreateIdea> batch;
  final Widget message;
  final bool replacing, preview;
  final List<({bool card, Widget child})> children;

  @override
  State<_IdeaBatch> createState() => _IdeaBatchState();
}

class _IdeaBatchState extends State<_IdeaBatch>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(vsync: this)
    ..addStatusListener(_finish);
  _BatchPhase _phase = _BatchPhase.idle;
  bool _started = false, _reduce = false, _fadingPlaceholders = false;
  late SmartWorkingColors _palette;
  Color? _seed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = Theme.of(context).colorScheme;
    if (colors.tertiary != _seed || _palette.brightness != colors.brightness) {
      _seed = colors.tertiary;
      _palette = SmartWorkingColors(colors.tertiary, colors.brightness);
    }
    _reduce = MediaQuery.disableAnimationsOf(context);
    if (!_started || _reduce) {
      _started = true;
      _start(widget.replacing ? _BatchPhase.waiting : _BatchPhase.arriving);
    }
  }

  @override
  void didUpdateWidget(_IdeaBatch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.replacing && !oldWidget.replacing) {
      _start(_BatchPhase.leaving);
    } else if (!widget.replacing &&
        oldWidget.replacing &&
        !widget.preview &&
        identical(widget.batch, oldWidget.batch)) {
      _start(_BatchPhase.restoring);
    } else if (!identical(widget.batch, oldWidget.batch) &&
        (widget.batch.length != oldWidget.batch.length ||
            widget.batch.indexed.any(
              (entry) => entry.$2.title != oldWidget.batch[entry.$1].title,
            ))) {
      final cancelledPreview = oldWidget.preview && !widget.preview;
      _start(cancelledPreview ? _BatchPhase.restoring : _BatchPhase.arriving);
    }
  }

  void _start(_BatchPhase next) {
    _fadingPlaceholders =
        !_reduce &&
        next == _BatchPhase.arriving &&
        _phase == _BatchPhase.waiting;
    if (_reduce) {
      _phase = widget.replacing ? _BatchPhase.waiting : _BatchPhase.idle;
      _motion.stop();
      return;
    }
    _phase = next;
    final lastIndex = (widget.children.length - 1).clamp(0, 20);
    final ms = switch (next) {
      _BatchPhase.leaving => 420,
      _BatchPhase.arriving => 820 + lastIndex * 70,
      _BatchPhase.restoring => 200 + lastIndex * 30,
      _ => 0,
    };
    if (ms > 0 && widget.children.isNotEmpty) {
      _motion.duration = Duration(milliseconds: ms);
      _motion.forward(from: 0);
    } else {
      _motion.stop();
      _phase = widget.replacing ? _BatchPhase.waiting : _BatchPhase.idle;
    }
  }

  void _finish(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    setState(() {
      if (_phase == _BatchPhase.leaving) {
        _phase = _BatchPhase.waiting;
      } else {
        _phase = _BatchPhase.idle;
      }
      _fadingPlaceholders = false;
    });
  }

  double _part(int start, int length, Curve curve) {
    final ms = _motion.value * _motion.duration!.inMilliseconds;
    return curve.transform(((ms - start) / length).clamp(0.0, 1.0));
  }

  Widget _motionItem(int index, ({bool card, Widget child}) item) {
    return AnimatedBuilder(
      animation: _motion,
      child: item.child,
      builder: (context, child) {
        if (_phase == _BatchPhase.idle) return child!;
        final leaving = _phase == _BatchPhase.leaving;
        final restoring = _phase == _BatchPhase.restoring;
        final t = leaving
            ? _part(index * 20, 220, const Cubic(.3, 0, .8, .15))
            : restoring
            ? _part(index * 30, 200, Curves.easeOut)
            : _part(index * 70, 320, const Cubic(.2, 0, 0, 1));
        final travel = leaving
            ? -6 * t
            : restoring
            ? 0.0
            : 14 * (1 - t);
        Widget contents = child!;
        if (item.card && _phase == _BatchPhase.arriving) {
          final glint = _part(index * 70 + 120, 700, Curves.easeInOut);
          if (glint > 0 && glint < 1) {
            contents = CustomPaint(
              foregroundPainter: _IdeaGlint(
                glint,
                _palette.splashes[2].withValues(
                  alpha: _palette.brightness == Brightness.dark ? .2 : .4,
                ),
              ),
              child: contents,
            );
          }
        }
        return Transform.translate(
          offset: Offset(0, travel),
          child: Transform.scale(
            scale: leaving
                ? 1 - .02 * t
                : restoring
                ? 1
                : .985 + .015 * t,
            child: Opacity(opacity: leaving ? 1 - t : t, child: contents),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final placeholders = _IdeaPlaceholders(palette: _palette, reduce: _reduce);
    return Stack(
      children: [
        if (_phase != _BatchPhase.waiting)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              widget.message,
              for (final (index, child) in widget.children.indexed)
                _motionItem(index, child),
            ],
          ),
        if (_phase == _BatchPhase.waiting || _fadingPlaceholders)
          // Change only the positioning at the swap, so the entrance and
          // ongoing shimmer keep their exact phase as the placeholders fade.
          Positioned(
            key: const ValueKey('idea-placeholders'),
            left: _fadingPlaceholders ? 0 : null,
            right: _fadingPlaceholders ? 0 : null,
            top: _fadingPlaceholders ? 0 : null,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _motion,
                child: placeholders,
                builder: (_, child) => Opacity(
                  opacity: _fadingPlaceholders
                      ? 1 - _part(0, 260, Curves.easeOut)
                      : 1,
                  child: child,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }
}

class _IdeaGlint extends CustomPainter {
  const _IdeaGlint(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Rect.fromLTRB(0, 8, size.width, size.height);
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        bounds,
        const Radius.circular(FaceliftTokens.cardRadius),
      ),
    );
    _paintSweep(canvas, bounds, color, progress, card: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IdeaGlint old) =>
      old.progress != progress || old.color != color;
}

void _paintSweep(
  Canvas canvas,
  Rect bounds,
  Color color,
  double t, {
  bool card = false,
}) {
  final clear = color.withValues(alpha: 0);
  final gradient = LinearGradient(
    begin: const Alignment(-1, -.22),
    end: const Alignment(1, .22),
    colors: [clear, color, clear],
    stops: [card ? .30 : .15, .5, card ? .70 : .85],
  );
  final sweep = bounds.shift(
    Offset((2 * t - 1) * bounds.width * (card ? 1.1 : 1), 0),
  );
  canvas.drawRect(bounds, Paint()..shader = gradient.createShader(sweep));
}

class _IdeaPlaceholders extends StatefulWidget {
  const _IdeaPlaceholders({required this.palette, required this.reduce});
  final SmartWorkingColors palette;
  final bool reduce;

  @override
  State<_IdeaPlaceholders> createState() => _IdeaPlaceholdersState();
}

class _IdeaPlaceholdersState extends State<_IdeaPlaceholders>
    with SingleTickerProviderStateMixin {
  late final _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.reduce) _shimmer.repeat();
  }

  @override
  void didUpdateWidget(_IdeaPlaceholders oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduce != widget.reduce) {
      if (widget.reduce) {
        _shimmer.stop();
      } else {
        _shimmer.repeat();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: double.infinity,
          height: 4 * 150,
          child: CustomPaint(
            painter: _PlaceholderPaint(
              _shimmer,
              widget.reduce,
              scheme.surfaceContainer,
              scheme.surfaceContainerHighest,
              widget.palette.splashes[1].withValues(
                alpha: scheme.brightness == Brightness.dark ? .12 : .33,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }
}

class _PlaceholderPaint extends CustomPainter {
  _PlaceholderPaint(
    this.shimmer,
    this.reduce,
    this.surface,
    this.fill,
    this.tint,
  ) : super(repaint: shimmer);
  final AnimationController shimmer;
  final bool reduce;
  final Color surface, fill, tint;

  @override
  void paint(Canvas canvas, Size size) {
    final elapsed = shimmer.lastElapsedDuration?.inMicroseconds ?? 0;
    for (var i = 0; i < 4; i++) {
      final enter = reduce
          ? 1.0
          : const Cubic(
              .2,
              0,
              0,
              1,
            ).transform(((elapsed / 1000 - i * 50) / 220).clamp(0.0, 1.0));
      if (enter == 0) continue;
      final top = 8.0 + i * 150;
      final rect = Rect.fromLTWH(0, top, size.width, 140);
      final shape = RRect.fromRectAndRadius(rect, const Radius.circular(20));
      canvas.save();
      canvas.clipRRect(shape);
      if (enter < 1) {
        canvas.saveLayer(
          rect,
          Paint()..color = Colors.white.withValues(alpha: enter),
        );
      }
      canvas.drawRect(rect, Paint()..color = surface);
      final bar = Paint()..color = fill;
      final width = (size.width - 32).clamp(0.0, size.width);
      void line(double y, double w, double h) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(16, top + y, w, h),
            const Radius.circular(8),
          ),
          bar,
        );
      }

      line(16, width * .62, 18);
      line(48, width * .90, 13);
      line(71, width * .68, 13);
      line(98, 124.0.clamp(0.0, width), 26);
      final ms = elapsed / 1000 - i * 120;
      if (!reduce && ms >= 0) {
        _paintSweep(
          canvas,
          rect,
          tint,
          Curves.easeInOut.transform((ms % 1600) / 1600),
        );
      }
      if (enter < 1) canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_PlaceholderPaint old) =>
      old.reduce != reduce ||
      old.surface != surface ||
      old.fill != fill ||
      old.tint != tint;
}
