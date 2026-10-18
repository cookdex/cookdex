import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// One policy for authored scroll views, including their implicit controllers.
/// Flutter's ScrollBehavior has no controller factory; the thin views below
/// supply a locally owned primary controller without changing their layout.
class CookdexScrollBehavior extends MaterialScrollBehavior {
  const CookdexScrollBehavior();

  ScrollController createController() => PixelScrollController();
}

class PixelScrollController extends ScrollController {
  PixelScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => PixelScrollPosition(
    physics: physics,
    context: context,
    initialPixels: initialScrollOffset,
    keepScrollOffset: keepScrollOffset,
    oldPosition: oldPosition,
    debugLabel: debugLabel,
  );
}

class PixelScrollPosition extends ScrollPositionWithSingleContext {
  PixelScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double _dragRemainder = 0;
  double? _lastRatio;
  double get _ratio => MediaQuery.devicePixelRatioOf(context.storageContext);
  double _snap(double value) => (value * _ratio).roundToDouble() / _ratio;

  @override
  void applyUserOffset(double delta) {
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    final raw =
        pixels - physics.applyPhysicsToUserOffset(this, delta) + _dragRemainder;
    final snapped = _snap(raw);
    // Rounding each event independently loses subpixel motion or changes drag
    // speed. Accumulate the remainder; only the rendered position is quantized.
    _dragRemainder = raw - snapped;
    if (super.setPixels(snapped) != 0) _dragRemainder = 0;
  }

  @override
  void goBallistic(double velocity) {
    _dragRemainder = 0;
    super.goBallistic(velocity);
  }

  @override
  double setPixels(double newPixels) => super.setPixels(_snap(newPixels));
  @override
  void correctPixels(double value) => super.correctPixels(_snap(value));
  @override
  void forcePixels(double value) {
    _dragRemainder = 0;
    super.forcePixels(_snap(value));
  }

  @override
  void correctBy(double correction) =>
      super.correctBy(_snap(pixels + correction) - pixels);

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    final ratio = _ratio;
    if (_lastRatio != ratio) {
      _lastRatio = ratio;
      _dragRemainder = 0;
      if (hasPixels) super.correctPixels(_snap(pixels));
    }
    // A fractional endpoint would otherwise undo snapping during clamping.
    final min = (minScrollExtent * ratio).ceilToDouble() / ratio;
    final max = math.max(
      min,
      (maxScrollExtent * ratio).floorToDouble() / ratio,
    );
    return super.applyContentDimensions(min, max);
  }
}

/// Owns a controller for the view only, never shares it with a nested view.
class PixelScrollScope extends StatefulWidget {
  const PixelScrollScope({
    super.key,
    required this.axis,
    required this.builder,
  });
  final Axis axis;
  final WidgetBuilder builder;
  @override
  State<PixelScrollScope> createState() => _PixelScrollScopeState();
}

class _PixelScrollScopeState extends State<PixelScrollScope> {
  ScrollController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final behavior = ScrollConfiguration.of(context);
    _controller ??= behavior is CookdexScrollBehavior
        ? behavior.createController()
        : PixelScrollController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PrimaryScrollController(
    controller: _controller!,
    scrollDirection: widget.axis,
    automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
    child: Builder(builder: widget.builder),
  );
}

class PixelListView extends ListView {
  PixelListView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.physics,
    super.shrinkWrap,
    super.padding,
    super.children,
    super.keyboardDismissBehavior,
  });
  PixelListView.builder({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.physics,
    super.shrinkWrap,
    super.padding,
    required super.itemBuilder,
    super.itemCount,
    super.keyboardDismissBehavior,
  }) : super.builder();
  @override
  Widget build(BuildContext context) => controller != null
      ? super.build(context)
      : PixelScrollScope(axis: scrollDirection, builder: super.build);
}

class PixelSingleChildScrollView extends SingleChildScrollView {
  const PixelSingleChildScrollView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.padding,
    super.controller,
    super.physics,
    super.child,
    super.keyboardDismissBehavior,
  });
  @override
  Widget build(BuildContext context) => controller != null
      ? super.build(context)
      : PixelScrollScope(axis: scrollDirection, builder: super.build);
}

class PixelCustomScrollView extends CustomScrollView {
  const PixelCustomScrollView({
    super.key,
    super.scrollDirection,
    super.reverse,
    super.controller,
    super.physics,
    super.shrinkWrap,
    super.slivers,
    super.keyboardDismissBehavior,
  });
  @override
  Widget build(BuildContext context) => controller != null
      ? super.build(context)
      : PixelScrollScope(axis: scrollDirection, builder: super.build);
}
