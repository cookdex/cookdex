import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A temporary scale picker that consumes Back while its options are open.
class RecipeScaleControl extends StatefulWidget {
  const RecipeScaleControl({
    super.key,
    required this.scale,
    required this.onSelected,
    required this.heading,
    required this.textScaler,
    this.enabled = true,
  });

  final int scale;
  final ValueChanged<int> onSelected;
  final Widget heading;
  final TextScaler textScaler;
  final bool enabled;

  @override
  State<RecipeScaleControl> createState() => _RecipeScaleControlState();
}

class _RecipeScaleControlState extends State<RecipeScaleControl> {
  final _scroll = ScrollController();
  LocalHistoryEntry? _entry;
  bool get _open => _entry != null;

  String _label(int scale) =>
      '${scale.isEven ? scale ~/ 2 : '${scale ~/ 2}.5'}×';

  void _close() => _entry?.remove();

  void _toggle(double optionWidth) {
    if (_open) {
      _close();
      return;
    }
    final entry = LocalHistoryEntry(
      onRemove: () {
        if (mounted && _entry != null) setState(() => _entry = null);
      },
    );
    setState(() => _entry = entry);
    ModalRoute.of(context)!.addLocalHistoryEntry(entry);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open || !_scroll.hasClients) return;
      final position = _scroll.position;
      _scroll.jumpTo(
        ((widget.scale - 1) * optionWidth -
                (position.viewportDimension - optionWidth) / 2)
            .clamp(0.0, position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    final entry = _entry;
    _entry = null;
    entry?.remove();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.labelLarge!;
    final measure = TextPainter(
      text: TextSpan(text: '4.5×', style: style),
      textScaler: widget.textScaler,
      textDirection: Directionality.of(context),
    )..layout();
    final diameter = math.max(
      48.0,
      math.max(measure.width, measure.height) + 20,
    );
    final optionWidth = math.max(48.0, measure.width + 24);
    measure.dispose();
    return TapRegion(
      consumeOutsideTaps: _open,
      onTapOutside: (_) => _close(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final heading = widget.heading;
          var headingWidth = 0.0;
          if (heading is Text) {
            final measureHeading = TextPainter(
              text:
                  heading.textSpan ??
                  TextSpan(
                    text: heading.data,
                    style: DefaultTextStyle.of(context).style
                        .merge(heading.style),
                  ),
              textScaler:
                  heading.textScaler ?? MediaQuery.textScalerOf(context),
              textDirection: Directionality.of(context),
            )..layout();
            headingWidth = measureHeading.width;
            measureHeading.dispose();
          }
          final stacked = headingWidth + diameter + 8 > constraints.maxWidth;
          final visibleHeading = ExcludeSemantics(
            excluding: _open,
            child: Opacity(opacity: _open ? 0 : 1, child: heading),
          );
          final controls = Stack(
            alignment: Alignment.centerRight,
            children: [
              if (stacked)
                SizedBox(width: double.infinity, height: diameter)
              else
                Row(
                  children: [
                    Expanded(child: visibleHeading),
                    const SizedBox(width: 8),
                    SizedBox.square(dimension: diameter),
                  ],
                ),
              Positioned(
                left: 0,
                right: diameter + 8,
                height: diameter,
                child: ClipRect(
                  child: IgnorePointer(
                    ignoring: !_open,
                    child: ExcludeSemantics(
                      excluding: !_open,
                      child: AnimatedSlide(
                        offset: _open ? Offset.zero : const Offset(1, 0),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Material(
                          color: colors.surfaceContainer,
                          borderRadius: BorderRadius.circular(diameter / 2),
                          clipBehavior: Clip.antiAlias,
                          child: SingleChildScrollView(
                            key: const Key('recipe-scale-options'),
                            controller: _scroll,
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (var scale = 1; scale <= 10; scale++)
                                  SizedBox(
                                    width: optionWidth,
                                    child: Semantics(
                                      selected: widget.scale == scale,
                                      child: TextButton(
                                        key: ValueKey('recipe-scale-$scale'),
                                        style: TextButton.styleFrom(
                                          minimumSize: Size(optionWidth, 48),
                                          padding: EdgeInsets.zero,
                                          backgroundColor: widget.scale == scale
                                              ? colors.primaryContainer
                                              : null,
                                          foregroundColor: widget.scale == scale
                                              ? colors.onPrimaryContainer
                                              : colors.onSurface,
                                        ),
                                        onPressed: !widget.enabled
                                            ? null
                                            : () {
                                                _close();
                                                widget.onSelected(scale);
                                              },
                                        child: Text(
                                          _label(scale),
                                          textScaler: widget.textScaler,
                                        ),
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
              SizedBox.square(
                dimension: diameter,
                child: Semantics(
                  expanded: _open,
                  child: TextButton(
                    key: const Key('recipe-scale-toggle'),
                    style: TextButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: EdgeInsets.zero,
                      backgroundColor: widget.scale != 2
                          ? colors.primaryContainer
                          : colors.surfaceContainer,
                      foregroundColor: widget.scale != 2
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                    ),
                    onPressed: widget.enabled
                        ? () => _toggle(optionWidth)
                        : null,
                    child: Text(
                      _label(widget.scale),
                      semanticsLabel: 'Recipe scale ${_label(widget.scale)}',
                      textScaler: widget.textScaler,
                    ),
                  ),
                ),
              ),
            ],
          );
          return stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    visibleHeading,
                    const SizedBox(height: 8),
                    controls,
                  ],
                )
              : controls;
        },
      ),
    );
  }
}
