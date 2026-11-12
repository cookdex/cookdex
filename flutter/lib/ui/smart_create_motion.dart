import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'facelift_motion.dart';

/// Keeps the natural layout of the supplied rows/wraps. When their contents
/// change, paint each surviving item from its previous position to its new one.
class CreateReflow extends StatefulWidget {
  const CreateReflow({
    super.key,
    required this.items,
    required this.layout,
    this.geometry,
    this.stagger = false,
    this.duration,
    this.arrivalScale = .78,
  });

  final Map<Object, Widget> items;
  final Widget Function(Map<Object, Widget> items) layout;
  final Object? geometry;
  final bool stagger;
  final Duration? duration;
  final double arrivalScale;

  @override
  State<CreateReflow> createState() => _CreateReflowState();
}

class _CreateReflowState extends State<CreateReflow>
    with SingleTickerProviderStateMixin {
  final _surface = GlobalKey();
  final _anchors = <Object, GlobalKey>{};
  final _from = <Object, Rect>{};
  final _leaving = <Object, Widget>{};
  final _arrival = <Object, int>{};
  late final _motion = AnimationController(vsync: this, value: 1)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _leaving.clear();
          _arrival.clear();
          _from.clear();
          _anchors.removeWhere((id, _) => !widget.items.containsKey(id));
        });
      }
    });

  Rect? _rect(Object id) {
    final box = _anchors[id]?.currentContext?.findRenderObject() as RenderBox?;
    final surface = _surface.currentContext?.findRenderObject();
    if (box == null || surface == null || !box.attached || !box.hasSize) {
      return null;
    }
    final painted = box is _RenderReflowSlide ? box.translation : Offset.zero;
    return box.localToGlobal(painted, ancestor: surface) & box.size;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = widget.duration == null
        ? FaceliftMotion.duration(context, MotionGroup.lists)
        : FaceliftMotion.accessible(context, widget.duration!);
    if (_motion.duration == null &&
        widget.stagger &&
        duration > Duration.zero) {
      for (final id in widget.items.keys) {
        _arrival[id] = _arrival.length;
      }
      _motion.duration = duration * 1.6;
      _motion.forward(from: 0);
    } else {
      _motion.duration = duration * (widget.stagger ? 1.6 : 1);
      if (duration == Duration.zero && _motion.value != 1) _motion.value = 1;
    }
  }

  @override
  void didUpdateWidget(CreateReflow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.geometry == widget.geometry &&
        listEquals(oldWidget.items.keys.toList(), widget.items.keys.toList())) {
      return;
    }
    if (_motion.duration == Duration.zero) {
      _anchors.removeWhere((id, _) => !widget.items.containsKey(id));
      return;
    }
    _from.clear();
    _leaving.clear();
    _arrival.clear();
    for (final entry in oldWidget.items.entries) {
      final rect = _rect(entry.key);
      if (rect == null) continue;
      _from[entry.key] = rect;
      if (!widget.items.containsKey(entry.key)) {
        _leaving[entry.key] = entry.value;
      }
    }
    for (final id in widget.items.keys) {
      if (!_from.containsKey(id)) _arrival[id] = _arrival.length;
    }
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pieces = <Object, Widget>{};
    for (final entry in widget.items.entries) {
      final id = entry.key;
      pieces[id] = AnimatedBuilder(
        key: _anchors.putIfAbsent(id, GlobalKey.new),
        animation: _motion,
        child: entry.value,
        builder: (_, child) {
          final index = _arrival[id];
          final start = widget.stagger && index != null
              ? (index * .07).clamp(0.0, .42)
              : 0.0;
          final t = Interval(
            start,
            1,
            curve: Curves.easeOutCubic,
          ).transform(_motion.value);
          return _ReflowSlide(
            surface: _surface,
            origin: _from[id]?.topLeft,
            remaining: 1 - t,
            arriving: index != null,
            child: index == null
                ? child!
                : Opacity(
                    opacity: t,
                    child: widget.stagger
                        ? child
                        : Transform.scale(
                            scale:
                                widget.arrivalScale +
                                (1 - widget.arrivalScale) * t,
                            child: child,
                          ),
                  ),
          );
        },
      );
    }
    return Stack(
      key: _surface,
      clipBehavior: Clip.none,
      children: [
        widget.layout(pieces),
        for (final entry in _leaving.entries)
          Positioned.fromRect(
            rect: _from[entry.key]!,
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: ReverseAnimation(_motion),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1, end: .78).animate(_motion),
                    child: entry.value,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A wrapping line can change midway through the chip's own avatar animation.
/// Resolve the laid-out destination at paint time so its first frame also
/// begins at the previous location, including during an interrupted move.
class _ReflowSlide extends SingleChildRenderObjectWidget {
  const _ReflowSlide({
    required this.surface,
    required this.origin,
    required this.remaining,
    required this.arriving,
    required super.child,
  });

  final GlobalKey surface;
  final Offset? origin;
  final double remaining;
  final bool arriving;

  @override
  _RenderReflowSlide createRenderObject(BuildContext context) =>
      _RenderReflowSlide(this);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReflowSlide renderObject,
  ) => renderObject.update(this);
}

class _RenderReflowSlide extends RenderProxyBox {
  _RenderReflowSlide(this.configuration);
  _ReflowSlide configuration;
  Offset translation = Offset.zero;

  void update(_ReflowSlide next) {
    configuration = next;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = configuration.origin;
    final ancestor = configuration.surface.currentContext?.findRenderObject();
    if (configuration.remaining == 0) {
      translation = Offset.zero;
    } else if (origin != null && ancestor != null) {
      translation =
          (origin - localToGlobal(Offset.zero, ancestor: ancestor)) *
          configuration.remaining;
    } else {
      translation = configuration.arriving
          ? Offset(0, 6 * configuration.remaining)
          : Offset.zero;
    }
    super.paint(context, offset + translation);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(translation.dx, translation.dy, 0, 1);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: translation,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );
}
