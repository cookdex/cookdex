part of 'smart_create_screen.dart';

extension _SmartCreateCheck on _SmartCreateScreenState {
  void _openIngredient() {
    if (_busy || _editingIngredient) return;
    _ingredientSettling = null;
    _ingredientScrollOrigin = _ingredientScroll?.pixels;
    _ingredientInset = View.of(context).viewInsets.bottom;
    _update(() => _editingIngredient = true);
    _ingredientFocus.requestFocus();
    _keepIngredientVisible();
  }

  void _commitIngredient() {
    final name = _ingredientInput.text.trim();
    _ingredientInput.clear();
    if (name.isNotEmpty) c.addIngredient(name);
  }

  ScrollPosition? get _ingredientScroll {
    final anchor = _ingredientFieldKey.currentContext;
    return anchor == null ? null : Scrollable.maybeOf(anchor)?.position;
  }

  void _closeIngredient({double? fromInset}) {
    if (!_editingIngredient || !mounted) return;
    final inset = View.of(context).viewInsets.bottom;
    final startInset = fromInset ?? inset;
    final pixels = _ingredientScroll?.pixels;
    final origin = _ingredientScrollOrigin;
    if (origin != null && pixels != null && pixels > origin && startInset > 0) {
      _ingredientSettling = (inset: startInset, pixels: pixels);
    }
    _update(() => _editingIngredient = false);
    _commitIngredient();
    _ingredientFocus.unfocus();
    _settleIngredientScroll(inset);
  }

  void _ingredientMetricsChanged() {
    if (!mounted || (!_editingIngredient && _ingredientSettling == null)) {
      return;
    }
    final inset = View.of(context).viewInsets.bottom;
    final previous = _ingredientInset;
    _ingredientInset = inset;
    if (!_editingIngredient) {
      _settleIngredientScroll(inset);
    } else if (inset < previous) {
      // Gboard keeps the field focused while sliding out. The first falling
      // native inset arrives before the final visibility/focus notification.
      _closeIngredient(fromInset: previous);
    } else if (inset > previous) {
      _keepIngredientVisible();
    }
  }

  void _settleIngredientScroll(double inset) {
    final start = _ingredientSettling;
    final origin = _ingredientScrollOrigin;
    if (start == null || origin == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _editingIngredient || _ingredientSettling != start) {
        return;
      }
      final scroll = _ingredientScroll;
      if (inset == 0 || scroll == null || !scroll.hasContentDimensions) {
        _ingredientSettling = null;
      }
      if (scroll == null || !scroll.hasContentDimensions) return;
      final remaining = (inset / start.inset).clamp(0.0, 1.0);
      final offset = (origin + (start.pixels - origin) * remaining).clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      );
      if ((scroll.pixels - offset).abs() > .5) scroll.jumpTo(offset);
    });
  }

  void _keepIngredientVisible({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final field = _ingredientFieldKey.currentContext;
      if (!mounted || !_editingIngredient || field == null) return;
      final target = field.findRenderObject();
      final scroll = Scrollable.of(field).position;
      if (target is! RenderBox ||
          !target.attached ||
          !scroll.hasContentDimensions) {
        return;
      }
      // Scaffold has laid out the viewport at this frame's native IME inset.
      // Reveal the whole field, including the confirm button and a little air.
      final bottom =
          RenderAbstractViewport.of(target)
              .getOffsetToReveal(target, 1)
              .offset +
          14;
      final offset = bottom.clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      );
      if (offset <= scroll.pixels + .5) return;
      final duration = _createDuration(context, 220);
      if (!animate || duration == Duration.zero) {
        scroll.jumpTo(offset);
      } else {
        scroll.animateTo(
          offset,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Widget _inlineIngredient() {
    void submit() {
      if (_busy || !_editingIngredient) return;
      _commitIngredient();
      _ingredientFocus.requestFocus();
      _keepIngredientVisible(animate: true);
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _createDuration(context, 180),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 4 * (1 - t)),
          child: Transform.scale(scale: .98 + .02 * t, child: child),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: TextFieldTapRegion(
          groupId: _ingredientFocus,
          consumeOutsideTaps: true,
          onTapOutside: (_) => _closeIngredient(),
          child: Focus(
            canRequestFocus: false,
            onFocusChange: (focused) {
              if (!focused) _closeIngredient();
            },
            child: TextField(
              controller: _ingredientInput,
              focusNode: _ingredientFocus,
              groupId: _ingredientFocus,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              // Keep the native editing connection across Return.
              onEditingComplete: () {},
              onSubmitted: (_) => submit(),
              scrollPadding: EdgeInsets.zero,
              decoration: InputDecoration(
                hintText: 'Add an ingredient',
                isDense: true,
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                  14,
                  10,
                  4,
                  10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(FaceliftTokens.tagRadius),
                ),
                suffixIcon: IconButton(
                  tooltip: 'Add ingredient',
                  onPressed: submit,
                  icon: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primary,
                    ),
                    child: SizedBox.square(
                      dimension: 30,
                      child: Center(
                        child: Icon(
                          Symbols.check,
                          size: 18,
                          weight: 600,
                          color: colors.onPrimary,
                        ),
                      ),
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

  Widget _options() => _panel(
    Column(
      key: _optionsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _optionsOpen,
          child: _DisclosureHeader(
            onTap: () => _update(() => _optionsOpen = !_optionsOpen),
            child: ListTile(
              title: const Text('Options'),
              subtitle: Text(
                "${c.meal == 'Any' ? 'Any meal' : c.meal} · ${c.effort == 'Any' ? 'Any effort' : c.effort} · ${_servingsLabel(c.servings)}",
              ),
              trailing: AnimatedRotation(
                turns: _optionsOpen ? .5 : 0,
                duration: _createDuration(context, _optionsOpen ? 242 : 220),
                curve: Curves.easeInOutCubic,
                child: Icon(
                  Symbols.expand_more,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        _CreateDisclosure(
          open: _optionsOpen,
          sectionKey: _optionsKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Meal', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    for (final meal in const [
                      'Any',
                      'Breakfast',
                      'Lunch',
                      'Dinner',
                      'Snack',
                      'Dessert',
                    ])
                      _OptionChip(
                        label: meal,
                        selected: c.meal == meal,
                        onTap: () => c.setOptions(meal: meal),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('Effort', style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                _EffortControl(
                  value: c.effort,
                  onChanged: (value) => c.setOptions(effort: value),
                ),
                const SizedBox(height: 12),
                _servingsControl(),
              ],
            ),
          ),
        ),
      ],
    ),
    padding: EdgeInsets.zero,
  );

  Widget _servingsControl() {
    final caption = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Servings', style: theme.textTheme.titleSmall),
        Text(
          'Default from Smart Create settings',
          style: FaceliftTokens.tileSubtitle(context),
        ),
      ],
    );
    final stepper = CreateCountStepper(
      value: c.servings,
      maximum: 99,
      noun: 'servings',
      onChanged: (value) => c.setOptions(servings: value),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = MediaQuery.textScalerOf(context).scale(14);
        if (constraints.maxWidth < 156 + size * 8) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [caption, const SizedBox(height: 4), stepper],
          );
        }
        return Row(
          children: [
            Expanded(child: caption),
            const SizedBox(width: 6),
            stepper,
          ],
        );
      },
    );
  }

  String _servingsLabel(int n) => '$n ${n == 1 ? 'serving' : 'servings'}';
  String get _ingredientCount =>
      "${c.ingredients.length} ${c.ingredients.length == 1 ? 'ingredient' : 'ingredients'}";

  List<Widget> _check() => [
    Text('Check your ingredients', style: theme.textTheme.titleLarge),
    const SizedBox(height: 4),
    Text(
      c.ingredients.isEmpty
          ? '0 ingredients. Add an ingredient to get ideas.'
          : '$_ingredientCount. Tap anything you want to use up first. × removes it.',
      style: FaceliftTokens.tileSubtitle(context),
    ),
    if (c.error == null) _message(),
    const SizedBox(height: 12),
    CreateReflow(
      duration: const Duration(milliseconds: 220),
      arrivalScale: .6,
      geometry: Object.hashAll([...c.ingredients, null, ...c.useFirst]),
      items: {
        for (final name in c.ingredients)
          name: InputChip(
            label: Text(name),
            selected: c.useFirst.contains(name),
            showCheckmark: false,
            selectedColor: colors.primaryContainer,
            avatar: c.useFirst.contains(name)
                ? const Icon(Symbols.timer, size: 17)
                : null,
            chipAnimationStyle: MediaQuery.disableAnimationsOf(context)
                ? ChipAnimationStyle(
                    selectAnimation: AnimationStyle.noAnimation,
                    avatarDrawerAnimation: AnimationStyle.noAnimation,
                    enableAnimation: AnimationStyle.noAnimation,
                  )
                : null,
            onSelected: (_) => c.toggleUseFirst(name),
            onDeleted: () => c.removeIngredient(name),
            deleteIcon: const Icon(Symbols.close, size: 16),
            deleteButtonTooltipMessage: 'Remove $name',
            shape: _chipShape,
          ),
        #add: AnimatedSwitcher(
          // The field has its own entrance. On dismiss, release the native
          // editor immediately and animate the button at its wrapping row.
          duration: _createDuration(context, _editingIngredient ? 0 : 200),
          switchInCurve: Curves.easeOutCubic,
          layoutBuilder: (current, _) => current ?? const SizedBox.shrink(),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: .85, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: _editingIngredient
              ? _inlineIngredient()
              : _dashedAction('Add', Symbols.add, _openIngredient),
        ),
        for (final name in c.maybe)
          name: _dashedAction(name, Symbols.help, () => c.acceptMaybe(name)),
      },
      layout: (items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: MediaQuery.textScalerOf(context).scale(14) > 16 ? 4 : 0,
            children: [
              for (final name in c.ingredients) items[name]!,
              KeyedSubtree(key: _ingredientFieldKey, child: items[#add]!),
            ],
          ),
          if (c.maybe.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Not sure about these. Tap to add.',
              style: theme.textTheme.titleSmall,
            ),
            Wrap(
              spacing: 6,
              children: [for (final name in c.maybe) items[name]!],
            ),
          ],
        ],
      ),
    ),
    const SizedBox(height: 14),
    _panel(
      ListTile(
        title: const Text('Staples you always have'),
        subtitle: Text(
          c.preferences.staples.isEmpty
              ? 'None selected'
              : c.preferences.staples.join(', '),
        ),
        trailing: TextButton(
          onPressed: () => widget.onStaples(context),
          child: const Text('Edit'),
        ),
      ),
      padding: EdgeInsets.zero,
    ),
  ];

  RoundedRectangleBorder get _chipShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(FaceliftTokens.tagRadius),
  );

  Widget _dashedAction(String label, IconData icon, VoidCallback action) =>
      TextButton.icon(
        style:
            TextButton.styleFrom(
              shape: _chipShape,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(40, 36),
            ).copyWith(
              backgroundBuilder: (context, states, child) => CustomPaint(
                foregroundPainter: _DashedOutline(
                  states.contains(WidgetState.disabled)
                      ? theme.disabledColor
                      : colors.outline,
                ),
                child: child,
              ),
            ),
        icon: Icon(icon, size: 16),
        onPressed: action,
        label: Text(label),
      );
}

Duration _createDuration(BuildContext context, int milliseconds) =>
    FaceliftMotion.accessible(context, Duration(milliseconds: milliseconds));

class _CreateScrollCurve extends Curve {
  const _CreateScrollCurve();

  @override
  double transformInternal(double t) {
    if (t < .5) return 4 * t * t * t;
    final remaining = 1 - t;
    return 1 - 4 * remaining * remaining * remaining;
  }
}

WidgetStateProperty<Color?> _disclosureOverlay(BuildContext context) {
  final focus = Theme.of(context).focusColor;
  return WidgetStateProperty.resolveWith(
    (states) =>
        states.contains(WidgetState.focused) ? focus : Colors.transparent,
  );
}

class _DisclosureHeader extends StatefulWidget {
  const _DisclosureHeader({required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_DisclosureHeader> createState() => _DisclosureHeaderState();
}

class _DisclosureHeaderState extends State<_DisclosureHeader> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: widget.onTap != null,
    onShowFocusHighlight: (value) => setState(() => _focused = value),
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onTap?.call();
          return null;
        },
      ),
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(FaceliftTokens.tagRadius),
          border: _focused
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: widget.child,
      ),
    ),
  );
}

/// Paints and clips the same body in both directions, so a closing card keeps
/// its contents for the entire fold. The scroll follows its final geometry.
class _CreateDisclosure extends StatefulWidget {
  const _CreateDisclosure({
    required this.open,
    required this.sectionKey,
    required this.child,
  });
  final bool open;
  final GlobalKey sectionKey;
  final Widget child;

  @override
  State<_CreateDisclosure> createState() => _CreateDisclosureState();
}

class _CreateDisclosureState extends State<_CreateDisclosure>
    with TickerProviderStateMixin {
  static const _emphasized = Cubic(.2, 0, 0, 1);
  final _bodyKey = GlobalKey();
  late final _fold = AnimationController(
    vsync: this,
    value: widget.open ? 1 : 0,
  );
  late final _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..addListener(_queueReveal);
  double? _startOffset;
  late bool _opening = widget.open;
  late double _startingOpacity = widget.open ? 1 : 0;
  bool _queued = false;
  bool get _reduced => MediaQuery.disableAnimationsOf(context);

  double get _opacity {
    if (!_opening) return _startingOpacity;
    if (!_fold.isAnimating) return 1;
    final elapsed = (_fold.lastElapsedDuration ?? Duration.zero).inMicroseconds;
    final t = ((elapsed - 40000) / 200000).clamp(0.0, 1.0);
    return _startingOpacity + (1 - _startingOpacity) * _emphasized.transform(t);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reduced) {
      _fold.value = widget.open ? 1 : 0;
      if (_reveal.isAnimating) {
        _reveal.value = 1;
      }
    }
  }

  @override
  void didUpdateWidget(_CreateDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    _startingOpacity = _fold.value == 0 ? 0 : _opacity;
    _opening = widget.open;
    _reveal.stop();
    _startOffset = null;
    if (_reduced) {
      _fold.value = widget.open ? 1 : 0;
      if (widget.open) {
        _reveal.value = 1;
        _queueReveal();
      }
    } else if (widget.open) {
      _fold.animateTo(
        1,
        duration: const Duration(milliseconds: 242),
        curve: _emphasized,
      );
      _reveal.forward(from: 0);
    } else {
      _fold.animateBack(
        0,
        duration: const Duration(milliseconds: 220),
        curve: _emphasized,
      );
    }
  }

  void _queueReveal() {
    if (_queued || !widget.open) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!mounted || !widget.open) return;
      final sectionContext = widget.sectionKey.currentContext;
      final section = sectionContext?.findRenderObject();
      final body = _bodyKey.currentContext?.findRenderObject();
      if (sectionContext == null ||
          section is! RenderBox ||
          body is! RenderBox ||
          !section.attached ||
          !body.attached) {
        return;
      }
      final scroll = Scrollable.of(sectionContext).position;
      if (!scroll.hasContentDimensions || scroll.isScrollingNotifier.value) {
        // A new user drag takes precedence over automatic reveal.
        _reveal.stop();
        return;
      }
      final from = _startOffset ??= scroll.pixels;
      final remainingHeight = body.size.height * (1 - _fold.value);
      final viewport = RenderAbstractViewport.of(section);
      final top = viewport.getOffsetToReveal(section, 0).offset - 8;
      final bottom =
          viewport.getOffsetToReveal(section, 1).offset + remainingHeight + 8;
      final preferTop =
          section.size.height + remainingHeight + 16 > scroll.viewportDimension;
      final to = preferTop || top < from
          ? top
          : bottom > from
          ? bottom
          : from;
      final progress = const _CreateScrollCurve().transform(_reveal.value);
      final offset = (from + (to - from) * progress).clamp(
        scroll.minScrollExtent,
        scroll.maxScrollExtent,
      );
      if ((offset - scroll.pixels).abs() > .5) scroll.jumpTo(offset);
    });
  }

  @override
  void dispose() {
    _fold.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fold,
    child: KeyedSubtree(key: _bodyKey, child: widget.child),
    builder: (context, child) {
      if (_fold.value == 0 && !widget.open) return const SizedBox.shrink();
      final t = _fold.value;
      final fade = _opacity;
      return ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: ExcludeFocus(
            excluding: !widget.open,
            child: ExcludeSemantics(
              excluding: !widget.open,
              child: IgnorePointer(
                ignoring: !widget.open,
                child: Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(0, -6 * (1 - fade)),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.bars = 0,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int bars;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ink = selected ? colors.onSecondaryContainer : colors.onSurface;
    final duration = _createDuration(context, 200);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FaceliftTokens.tagRadius),
          ),
          side: BorderSide(
            color: selected ? Colors.transparent : colors.outline,
          ),
          backgroundColor: selected
              ? colors.secondaryContainer
              : Colors.transparent,
          foregroundColor: ink,
          animationDuration: duration,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              duration: duration,
              curve: Curves.easeOutCubic,
              tween: Tween(end: selected ? 1 : 0),
              child: const Padding(
                padding: EdgeInsetsDirectional.only(end: 5),
                child: Icon(Symbols.check, size: 17),
              ),
              builder: (_, t, check) => ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: t,
                  child: Transform.scale(scale: t, child: check),
                ),
              ),
            ),
            if (bars > 0) ...[
              CreateEffortBars(bars, ink),
              const SizedBox(width: 4),
            ],
            Text(label),
          ],
        ),
      ),
    );
  }
}

class _EffortControl extends StatelessWidget {
  const _EffortControl({required this.value, required this.onChanged});
  static const values = ['Any', 'Easy', 'Medium', 'Involved'];
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final style = theme.textTheme.labelLarge!;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve each label's selected width so the segments stay put as the
        // pill moves. Easy, Medium and Involved also have three bars and a gap.
        final measure = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: scaler,
        );
        final selectedStyle = style.copyWith(fontWeight: FontWeight.w600);
        final segmentWidths = <double>[];
        for (final (i, label) in values.indexed) {
          measure.text = TextSpan(text: label, style: selectedStyle);
          measure.layout();
          final width = measure.width.ceilToDouble() + 16 + (i == 0 ? 0 : 18.5);
          segmentWidths.add(width < 48 ? 48 : width);
        }
        measure.dispose();
        final requiredWidth = segmentWidths.reduce((a, b) => a + b);
        final availableWidth = constraints.maxWidth - 6;
        if (requiredWidth > availableWidth) {
          return Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final (i, label) in values.indexed)
                _OptionChip(
                  label: label,
                  selected: value == label,
                  onTap: () => onChanged(label),
                  bars: i,
                ),
            ],
          );
        }
        final extra = (availableWidth - requiredWidth) / values.length;
        final widths = [for (final width in segmentWidths) width + extra];
        final selected = values.indexOf(value);
        return DecoratedBox(
          decoration: ShapeDecoration(
            shape: StadiumBorder(side: BorderSide(color: colors.outline)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Stack(
              children: [
                if (selected >= 0)
                  AnimatedPositionedDirectional(
                    duration: _createDuration(context, 260),
                    curve: Curves.easeInOutCubic,
                    top: 3,
                    bottom: 3,
                    start: widths
                        .take(selected)
                        .fold<double>(0, (a, b) => a + b),
                    width: widths[selected],
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        shape: StadiumBorder(
                          side: BorderSide(color: colors.primary),
                        ),
                        color: colors.secondaryContainer,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (final (i, label) in values.indexed)
                      SizedBox(
                        width: widths[i],
                        child: Semantics(
                          selected: value == label,
                          inMutuallyExclusiveGroup: true,
                          button: true,
                          child: InkWell(
                            onTap: () => onChanged(label),
                            customBorder: const StadiumBorder(),
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: _disclosureOverlay(context),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (i > 0) ...[
                                    CreateEffortBars(
                                      i,
                                      value == label
                                          ? colors.onSecondaryContainer
                                          : colors.primary,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    label,
                                    style: style.copyWith(
                                      fontWeight: value == label
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: value == label
                                          ? colors.onSecondaryContainer
                                          : colors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
