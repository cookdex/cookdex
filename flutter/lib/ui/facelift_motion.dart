import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

enum MotionGroup {
  tabs(240, .65),
  sheets(250, .90),
  lists(220, .90),
  floating(300, .75),
  cook(230, .75),
  star(180, .50),
  recipeOpening(450, .80),
  cookEntry(250, 1);

  const MotionGroup(this.milliseconds, this.defaultSpeed);
  final int milliseconds;
  final double defaultSpeed;
}

/// Preview settings stay in this app session, outside recipe preferences.
class MotionSettings extends ChangeNotifier {
  final _speeds = <MotionGroup, double>{};
  int _checkOffMs = FaceliftMotion.defaultCheckOffMs;

  int get checkOffMs => _checkOffMs;
  void setCheckOffMs(int value) {
    _checkOffMs = value.clamp(0, 1000);
    notifyListeners();
  }

  double speed(MotionGroup group) => _speeds[group] ?? group.defaultSpeed;
  void setSpeed(MotionGroup group, double speed) {
    _speeds[group] = speed.clamp(.5, 1.5);
    notifyListeners();
  }
}

class FaceliftMotion extends InheritedNotifier<MotionSettings> {
  const FaceliftMotion({
    super.key,
    required MotionSettings settings,
    required super.child,
  }) : super(notifier: settings);

  static const defaultCheckOffMs = 350;
  static Duration checkOffDelay(BuildContext context) => Duration(
    milliseconds: settingsOf(context)?.checkOffMs ?? defaultCheckOffMs,
  );

  // Existing motion outside the preview groups retains its release timing.
  static const themeFade = Duration(milliseconds: 150);
  static const titleFade = Duration(milliseconds: 150);
  static const scaleReveal = Duration(milliseconds: 180);
  static const statusFade = Duration(milliseconds: 200);
  static const topDeparture = Duration(milliseconds: 220);
  static const topLanding = Duration(milliseconds: 500);

  static Duration accessible(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;

  static MotionSettings? settingsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FaceliftMotion>()?.notifier;

  static double speedOf(BuildContext context, MotionGroup group) =>
      settingsOf(context)?.speed(group) ?? group.defaultSpeed;

  static Duration cookIngredientDuration(BuildContext context) =>
      duration(context, MotionGroup.cookEntry, fraction: 2);

  static Duration duration(
    BuildContext context,
    MotionGroup group, {
    double fraction = 1,
  }) {
    if (MediaQuery.disableAnimationsOf(context)) return Duration.zero;
    final speed = speedOf(context, group);
    return Duration(
      milliseconds: (group.milliseconds * fraction / speed).round(),
    );
  }
}

Color mutedDeleteColor(ColorScheme colors) =>
    Color.lerp(colors.error, colors.onSurfaceVariant, .17)!;

class FaceliftIconTile extends StatelessWidget {
  const FaceliftIconTile(
    this.icon, {
    super.key,
    this.accent = false,
    this.size = 44,
    this.fill,
  });
  final IconData icon;
  final bool accent;
  final double size;
  final double? fill;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent ? colors.tertiaryContainer : colors.primaryContainer,
        borderRadius: BorderRadius.circular(size * .3),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: size * .55,
        fill: fill,
        color: accent ? colors.onTertiaryContainer : colors.onPrimaryContainer,
      ),
    );
  }
}

/// A tap-only overlay keeps the scrollable card and its prepared shell identical
/// in layout and cost. Anchor it to the painted icon while the list can move.
void popCardStar(BuildContext rowContext, bool favorite) {
  final duration = FaceliftMotion.duration(rowContext, MotionGroup.star);
  if (duration == Duration.zero) return;
  RenderBox? anchor;
  void findStar(Element element) {
    if (anchor != null) return;
    final widget = element.widget;
    if (widget is Icon && widget.icon == Symbols.star) {
      anchor = element.findRenderObject() as RenderBox?;
    } else {
      element.visitChildren(findStar);
    }
  }

  rowContext.visitChildElements(findStar);
  final box = anchor;
  final overlay = Overlay.maybeOf(rowContext);
  if (box == null || overlay == null) return;
  final overlayBox = overlay.context.findRenderObject() as RenderBox;
  final size = box.size.shortestSide;
  final color = Theme.of(rowContext).colorScheme.tertiary;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: TweenAnimationBuilder<double>(
            duration: duration,
            tween: Tween(begin: 0, end: 1),
            onEnd: () {
              entry.remove();
              entry.dispose();
            },
            child: Icon(
              Symbols.star,
              fill: favorite ? 1 : 0,
              color: color,
              size: size,
            ),
            builder: (_, value, icon) {
              if (!box.attached ||
                  !overlayBox.attached ||
                  !rowContext.mounted) {
                return const SizedBox.shrink();
              }
              final origin = box.localToGlobal(
                Offset.zero,
                ancestor: overlayBox,
              );
              return Stack(
                children: [
                  Positioned(
                    left: origin.dx,
                    top: origin.dy,
                    child: Transform.scale(
                      scale: 1 + .19 * math.sin(math.pi * value),
                      child: icon,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

class FavoriteStar extends StatefulWidget {
  const FavoriteStar({super.key, required this.favorite, this.size});
  final bool favorite;
  final double? size;
  @override
  State<FavoriteStar> createState() => _FavoriteStarState();
}

class _FavoriteStarState extends State<FavoriteStar>
    with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this, value: 1);
  @override
  void didUpdateWidget(FavoriteStar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favorite != widget.favorite) {
      _pop.duration = FaceliftMotion.duration(context, MotionGroup.star);
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pop,
    child: Icon(
      Symbols.star,
      fill: widget.favorite ? 1 : 0,
      size: widget.size,
      color: Theme.of(context).colorScheme.tertiary,
    ),
    builder: (_, child) => Transform.scale(
      scale: 1 + .19 * math.sin(math.pi * _pop.value),
      child: child,
    ),
  );
}
