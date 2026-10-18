import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Classify the whole window, before rail or pane insets are applied.
enum WindowSizeClass {
  compact,
  medium,
  expanded;

  static WindowSizeClass of(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width < 600
        ? compact
        : width < 840
        ? medium
        : expanded;
  }
}

/// Compose recipe sizing with the system's (possibly nonlinear) text scaler.
class RecipeTextScaler extends TextScaler {
  const RecipeTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize * factor);
  @override
  double get textScaleFactor => system.scale(14 * factor) / 14;
  @override
  bool operator ==(Object other) =>
      other is RecipeTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

/// Keep the necessary MediaQuery copy local to this inherited-data adapter.
/// Its stable child does not rebuild for unrelated keyboard animation frames.
class RecipeTextScale extends StatelessWidget {
  const RecipeTextScale({super.key, required this.factor, required this.child});
  final double factor;
  final Widget child;
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: RecipeTextScaler(MediaQuery.textScalerOf(context), factor),
    ),
    child: child,
  );
}

/// Report laid-out footer height, including wrapping and accessibility text.
class MeasureHeight extends SingleChildRenderObjectWidget {
  const MeasureHeight({
    super.key,
    required this.onChanged,
    required super.child,
  });
  final ValueChanged<double> onChanged;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureHeight(onChanged);
  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _MeasureHeight).onChanged = onChanged;
  }
}

class _MeasureHeight extends RenderProxyBox {
  _MeasureHeight(this.onChanged);
  ValueChanged<double> onChanged;
  double? _height;
  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_height == height) return;
    _height = height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached && _height == height) onChanged(height);
    });
  }
}
