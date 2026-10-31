import 'package:flutter/material.dart';

/// Paint-only motion around a stable button, outside the recipe slivers.
class RecipeActionMotion extends StatelessWidget {
  const RecipeActionMotion({
    super.key,
    required this.visible,
    required this.child,
    this.slide = true,
  });

  final bool visible;
  final bool slide;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: visible ? 300 : 180);
    final curve = visible
        ? Easing.emphasizedDecelerate
        : Easing.emphasizedAccelerate;
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedSlide(
            duration: duration,
            curve: curve,
            offset: visible || !slide ? Offset.zero : const Offset(0, .3),
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: duration,
              curve: curve,
              child: AnimatedScale(
                scale: visible ? 1 : .9,
                duration: duration,
                curve: curve,
                child: RepaintBoundary(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
