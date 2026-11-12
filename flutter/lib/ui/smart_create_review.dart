import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../src/rust/api.dart' show Recipe;
import 'facelift_tokens.dart';
import 'smart_action_button.dart';

const _enter = Cubic(.2, 0, 0, 1);
const _leave = Cubic(.3, 0, .8, .15);

/// The review and its saved sheet share a route. A single reverse transition
/// can reveal Ideas beneath both, including on Android Back.
PageRoute<Recipe> smartCreateReviewRoute(
  BuildContext context, {
  required Widget Function(ValueChanged<Recipe> onSaved) buildEditor,
  required ValueChanged<Recipe> onLeave,
  required PageRoute<void> Function(BuildContext, Recipe, double)
  buildRecipeRoute,
}) {
  final still = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<Recipe>(
    allowSnapshotting: false,
    transitionDuration: Duration(milliseconds: still ? 0 : 320),
    reverseTransitionDuration: Duration(milliseconds: still ? 0 : 250),
    pageBuilder: (_, progress, _) => _Review(
      progress: progress,
      buildEditor: buildEditor,
      onLeave: onLeave,
      buildRecipeRoute: buildRecipeRoute,
    ),
  );
}

class _Review extends StatefulWidget {
  const _Review({
    required this.progress,
    required this.buildEditor,
    required this.onLeave,
    required this.buildRecipeRoute,
  });
  final Animation<double> progress;
  final Widget Function(ValueChanged<Recipe>) buildEditor;
  final ValueChanged<Recipe> onLeave;
  final PageRoute<void> Function(BuildContext, Recipe, double) buildRecipeRoute;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> with SingleTickerProviderStateMixin {
  late final _sheet = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1030),
  );
  Recipe? _saved;
  bool _leaving = false;
  PageRoute<void>? _replacement;
  double _drag = 0;
  late Widget _editor;

  @override
  void initState() {
    super.initState();
    _editor = widget.buildEditor(_didSave);
  }

  void _didSave(Recipe recipe) {
    setState(() => _saved = recipe);
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheet.value = 1;
    } else {
      _sheet.forward(from: 0);
    }
  }

  void _leaveSheet(bool view) {
    final recipe = _saved;
    if (_leaving || recipe == null) return;
    setState(() => _leaving = true);
    _sheet.stop();
    widget.onLeave(recipe);
    if (view) {
      final route = _replacement = widget.buildRecipeRoute(
        context,
        recipe,
        _sheet.value,
      );
      Navigator.of(context)
          .pushReplacement<void, Recipe>(route, result: recipe);
    } else {
      Navigator.of(context).pop(recipe);
    }
  }

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final scheme = Theme.of(context).colorScheme;
    final decorated = saved == null
        ? null
        : _SavedSheet(
            recipeName: saved.fields.title,
            progress: _sheet,
            onView: () => _leaveSheet(true),
            onBack: () => _leaveSheet(false),
          );
    return PopScope<Recipe>(
      canPop: saved == null || _leaving,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && saved != null) _leaveSheet(false);
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _sheet,
          widget.progress,
          _replacement?.animation,
        ]),
        child: _editor,
        builder: (context, editor) {
          final reversing = widget.progress.status == AnimationStatus.reverse;
          final away = reversing
              ? _leave.transform(1 - widget.progress.value)
              : 1 - _enter.transform(widget.progress.value);
          final time = _sheet.value * 1030;
          final exiting = reversing ? away : 0.0;
          final sheetPosition = _enter.transform((time / 320).clamp(0, 1));
          final scrim = Curves.easeOut.transform((time / 250).clamp(0, 1));
          return Stack(
            fit: StackFit.expand,
            children: [
              FractionalTranslation(
                translation: Offset(away, 0),
                child: ExcludeSemantics(
                  excluding: saved != null,
                  child: ExcludeFocus(excluding: saved != null, child: editor!),
                ),
              ),
              // Flutter lays out a new route offstage before its first visible
              // frame. Keep the sheet here until that route actually presents.
              if (saved != null &&
                  (_replacement == null ||
                      _replacement!.offstage ||
                      (_replacement!.animation?.value ?? 0) == 0)) ...[
                ModalBarrier(
                  color: scheme.scrim.withValues(
                    alpha:
                        (scheme.brightness == Brightness.dark ? .55 : .38) *
                        scrim *
                        (1 - exiting),
                  ),
                  dismissible: !_leaving,
                  onDismiss: () => _leaveSheet(false),
                  semanticsLabel: MaterialLocalizations.of(context)
                      .modalBarrierDismissLabel,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionalTranslation(
                    translation: Offset(
                      0,
                      1.05 * (1 - sheetPosition * (1 - exiting)),
                    ),
                    child: GestureDetector(
                      onVerticalDragStart: (_) => _drag = 0,
                      onVerticalDragUpdate: (d) => _drag += d.primaryDelta ?? 0,
                      onVerticalDragEnd: (d) {
                        if (_drag > 32 || (d.primaryVelocity ?? 0) > 300) {
                          _leaveSheet(false);
                        }
                      },
                      child: decorated!,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

PageRoute<void> savedSmartCreateRecipeRoute(
  BuildContext context, {
  required WidgetBuilder builder,
  required Recipe recipe,
  required double sheetProgress,
}) => _SavedRecipeRoute(
  builder: builder,
  recipe: recipe,
  sheetProgress: sheetProgress,
  reduced: MediaQuery.disableAnimationsOf(context),
);

/// Keep the saved sheet's handoff on entry, then let Material handle Back
/// (including Android's interactive preview and cancellation).
class _SavedRecipeRoute extends MaterialPageRoute<void> {
  _SavedRecipeRoute({
    required super.builder,
    required this.recipe,
    required this.sheetProgress,
    required this.reduced,
  }) : super(allowSnapshotting: false);
  final Recipe recipe;
  final double sheetProgress;
  final bool reduced;
  bool _presented = false;

  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : const Duration(milliseconds: 320);
  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : super.reverseTransitionDuration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (animation.isCompleted) _presented = true;
    if (_presented || reduced) {
      return super.buildTransitions(
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return _savedRecipeTransition(
      context,
      animation,
      child,
      recipe,
      sheetProgress,
    );
  }
}

Widget _savedRecipeTransition(
  BuildContext context,
  Animation<double> animation,
  Widget page,
  Recipe recipe,
  double sheetProgress,
) {
  final forward = animation.status == AnimationStatus.forward;
  final drop = _leave.transform((animation.value * 320 / 250).clamp(0, 1));
  final scheme = Theme.of(context).colorScheme;
  return Stack(
    fit: StackFit.expand,
    children: [
      SlideTransition(
        position: Tween(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).chain(CurveTween(curve: _enter)).animate(animation),
        child: page,
      ),
      // Paint the departing sheet above the entire incoming route until it has
      // dropped. Painting it on the outgoing review would clip it at the page edge.
      if (forward && animation.value > 0 && drop < 1) ...[
        IgnorePointer(
          child: ColoredBox(
            color: scheme.scrim.withValues(
              alpha:
                  (scheme.brightness == Brightness.dark ? .55 : .38) *
                  (1 - drop),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: FractionalTranslation(
            translation: Offset(0, 1.05 * drop),
            child: ExcludeSemantics(
              child: IgnorePointer(
                child: _SavedSheet(
                  recipeName: recipe.fields.title,
                  progress: AlwaysStoppedAnimation(sheetProgress),
                  onView: () {},
                  onBack: () {},
                ),
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _SavedSheet extends StatelessWidget {
  const _SavedSheet({
    required this.recipeName,
    required this.progress,
    required this.onView,
    required this.onBack,
  });
  final String recipeName;
  final Animation<double> progress;
  final VoidCallback onView, onBack;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = SmartWorkingColors(scheme.tertiary, scheme.brightness);
    final content = [
      Text(
        'Saved to your recipes',
        textAlign: TextAlign.center,
        style: FaceliftTokens.sheetTitle(context),
      ),
      Text(
        recipeName,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      FilledButton.icon(
        onPressed: onView,
        icon: const Icon(Symbols.menu_book),
        label: const Text('View recipe'),
      ),
      FilledButton.tonal(onPressed: onBack, child: const Text('Back to ideas')),
    ];
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: AnimatedBuilder(
              animation: progress,
              builder: (context, _) {
                final ms = progress.value * 1030;
                double interval(int start, int length) =>
                    ((ms - start) / length).clamp(0, 1);
                final pop = Curves.easeOut.transform(interval(120, 360));
                final ring = Curves.easeOut.transform(interval(380, 650));
                final scale = pop < .7
                    ? .6 + .46 * pop / .7
                    : 1.06 - .06 * (pop - .7) / .3;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    Center(
                      child: Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: (pop / .7).clamp(0, 1),
                          child: SizedBox.square(
                            dimension: 64,
                            child: Stack(
                              clipBehavior: Clip.none,
                              fit: StackFit.expand,
                              children: [
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: colors.base.take(4).toList(),
                                    ),
                                  ),
                                ),
                                if (ring > 0 && ring < 1)
                                  Transform.scale(
                                    scale: 1 + .7 * ring,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: colors.splashes[2].withValues(
                                            alpha: .9 * (1 - ring),
                                          ),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                Center(
                                  child: CustomPaint(
                                    size: const Size.square(34),
                                    painter: _SavedCheck(
                                      colors.ink,
                                      Curves.easeOut.transform(
                                        interval(300, 280),
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
                    for (final (index, item) in content.indexed)
                      Padding(
                        padding: EdgeInsets.only(
                          top: [14.0, 4.0, 18.0, 6.0][index],
                        ),
                        child: Opacity(
                          opacity: interval(180 + 50 * index, 240),
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              8 * (1 - interval(180 + 50 * index, 240)),
                            ),
                            child: index < 2
                                ? item
                                : ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      minHeight: 48,
                                    ),
                                    child: item,
                                  ),
                          ),
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
  }
}

class _SavedCheck extends CustomPainter {
  const _SavedCheck(this.color, this.progress);
  final Color color;
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(8.5, 17.7)
      ..lineTo(14.2, 23.4)
      ..lineTo(25.5, 10.6);
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.25
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SavedCheck old) =>
      old.progress != progress || old.color != color;
}
