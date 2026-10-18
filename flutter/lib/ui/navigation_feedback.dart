import 'package:flutter/material.dart';

import 'retained_screen.dart';

/// Declarative tab routes need the same painted surface as imperative forms.
class OpaqueMaterialPage<T> extends MaterialPage<T> {
  OpaqueMaterialPage({required Widget child, super.key, super.name})
    : super(
        child: Builder(
          builder: (context) => ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: RetainedScreen(child: SizedBox.expand(child: child)),
          ),
        ),
      );

  @override
  Route<T> createRoute(BuildContext context) => _OpaquePageRoute<T>(this);
}

// A nested navigator's current route can still belong to an invisible tab or
// sit underneath a root dialog/form. Check live ancestors, not frozen children.
bool _canPreview(PageRoute<dynamic> route) {
  if (WidgetsBinding.instance.platformDispatcher.views.any(
    (view) => view.viewInsets.bottom > 0,
  )) {
    return false;
  }
  var navigator = route.navigator;
  while (navigator != null) {
    final context = navigator.context;
    if (!TickerMode.valuesOf(context).enabled) return false;
    final parent = ModalRoute.of(context);
    if (parent == null) return true;
    if (!parent.isCurrent) return false;
    navigator = parent.navigator;
  }
  return true;
}

class _OpaquePageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  _OpaquePageRoute(OpaqueMaterialPage<T> page) : super(settings: page);
  OpaqueMaterialPage<T> get _page => settings as OpaqueMaterialPage<T>;
  @override
  Widget buildContent(BuildContext context) => _page.child;
  @override
  bool get maintainState => true;
  @override
  bool get popGestureEnabled => _canPreview(this) && super.popGestureEnabled;
}

/// Shared Material route feedback, including the Android predictive gesture.
class CookdexPageTransitionsBuilder extends PageTransitionsBuilder {
  const CookdexPageTransitionsBuilder(this.delegate);

  final PageTransitionsBuilder delegate;

  @override
  Duration get transitionDuration => delegate.transitionDuration;

  @override
  Duration get reverseTransitionDuration => delegate.reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition {
    final transition = delegate.delegatedTransition;
    if (transition == null) return null;
    return (context, animation, secondaryAnimation, allowSnapshotting, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return transition(
        context,
        animation,
        secondaryAnimation,
        allowSnapshotting,
        child,
      );
    };
  }

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : delegate.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}

/// Use for every pushed page, including pages in retained tab Navigators.
MaterialPageRoute<T> cookdexRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  RouteSettings? settings,
}) => _CookdexPageRoute<T>(
  builder: builder,
  settings: settings,
  reducedMotion: MediaQuery.disableAnimationsOf(context),
);

class _CookdexPageRoute<T> extends MaterialPageRoute<T> {
  _CookdexPageRoute({
    required super.builder,
    super.settings,
    required this.reducedMotion,
  });

  final bool reducedMotion;
  _PredictiveFormBackGuardState? _guard;
  bool _committingGuard = false;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => ColoredBox(
    // Route opacity controls visibility of the route beneath, but does not paint
    // a background. Detail pages share the shell's Scaffold, so the page itself
    // must own a surface inside the predictive gesture's scale and rounded clip.
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SizedBox.expand(
      child: RetainedScreen(
        child: super.buildPage(context, animation, secondaryAnimation),
      ),
    ),
  );

  @override
  bool get popGestureEnabled {
    if (!_canPreview(this)) return false;
    // A registered form may preview while its PopScope still protects Back.
    // Never relax the pop policy of unrelated routes or internal overlays.
    if (_guard?.widget.enabled != true || _committingGuard) {
      return super.popGestureEnabled;
    }
    return !isFirst && !willHandlePopInternally && animation!.isCompleted;
  }

  @override
  void handleCommitBackGesture() {
    final guard = _guard;
    if (guard == null) {
      super.handleCommitBackGesture();
      return;
    }
    // Material normally calls Navigator.pop directly on gesture commit. Settle
    // the preview first, then let the form confirm and persist before popping.
    _committingGuard = true;
    guard.widget.onCommit?.call();
    super.handleCancelBackGesture();
    void settled() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _committingGuard = false;
        if (isCurrent && identical(_guard, guard) && guard.mounted) {
          guard.widget.onBack();
        }
      });
    }

    if (animation!.isCompleted) {
      settled();
    } else {
      late AnimationStatusListener listener;
      listener = (status) {
        if (status == AnimationStatus.completed) {
          animation!.removeStatusListener(listener);
          settled();
        }
      };
      animation!.addStatusListener(listener);
    }
  }

  @override
  Duration get transitionDuration =>
      reducedMotion ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration =>
      reducedMotion ? Duration.zero : super.reverseTransitionDuration;
}

/// Explicitly permits a form to preview Back without bypassing its leave guard.
/// The usual PopScope and toolbar/Escape handler remain the source of truth.
class PredictiveFormBackGuard extends StatefulWidget {
  const PredictiveFormBackGuard({
    super.key,
    required this.enabled,
    required this.onBack,
    required this.child,
    this.onCommit,
  });
  final bool enabled;
  final VoidCallback onBack;

  /// Cancel asynchronous work immediately, before the preview settles.
  final VoidCallback? onCommit;
  final Widget child;

  @override
  State<PredictiveFormBackGuard> createState() =>
      _PredictiveFormBackGuardState();
}

class _PredictiveFormBackGuardState extends State<PredictiveFormBackGuard> {
  _CookdexPageRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (identical(_route, route)) return;
    _detach();
    if (route is _CookdexPageRoute<dynamic>) {
      _route = route;
      route._guard = this;
    }
  }

  void _detach() {
    if (identical(_route?._guard, this)) _route?._guard = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A fade-through between destinations that retains each tab's state and routes.
class RetainedTabTransition extends StatefulWidget {
  const RetainedTabTransition({
    super.key,
    required this.index,
    required this.children,
    this.backProgress,
    this.backFromRight = false,
  });

  final int index;
  final List<Widget> children;
  final double? backProgress;
  final bool backFromRight;

  @override
  State<RetainedTabTransition> createState() => _RetainedTabTransitionState();
}

class _RetainedTabTransitionState extends State<RetainedTabTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 240),
        value: 1,
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && _outgoing != null) {
          setState(() => _outgoing = null);
        }
      });
  int? _outgoing;

  @override
  void didUpdateWidget(RetainedTabTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _outgoing = null;
        _animation.value = 1;
      } else {
        _outgoing = oldWidget.index;
        _animation.forward(from: 0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _outgoing = null;
      _animation.value = 1;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) {
      final progress = _animation.value;
      final incoming = const Interval(
        .35,
        1,
        curve: Curves.easeOutCubic,
      ).transform(progress);
      final outgoing = 1 - const Interval(0, .35).transform(progress);
      final preview = widget.backProgress;
      final previewAmount = MediaQuery.disableAnimationsOf(context)
          ? 0.0
          : preview ?? 0.0;
      return Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < widget.children.length; i++)
            Offstage(
              offstage: preview != null
                  ? i != widget.index && i != 0
                  : i != widget.index && i != _outgoing,
              child: TickerMode(
                enabled: i == widget.index,
                child: IgnorePointer(
                  ignoring: i != widget.index || incoming < 1,
                  child: ExcludeSemantics(
                    excluding: i != widget.index,
                    child: Opacity(
                      opacity: preview != null
                          ? 1
                          : i == widget.index
                          ? incoming
                          : outgoing,
                      child: Transform.translate(
                        offset: i == widget.index
                            ? Offset(
                                (widget.backFromRight ? -1 : 1) *
                                    28 *
                                    previewAmount,
                                0,
                              )
                            : Offset.zero,
                        child: Transform.scale(
                          scale: i == widget.index
                              ? (preview != null
                                    ? 1 - .06 * previewAmount
                                    : .96 + .04 * incoming)
                              : 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              i == widget.index ? 24 * previewAmount : 0,
                            ),
                            child: ColoredBox(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: RetainedScreen(
                                visible: i == widget.index,
                                child: widget.children[i],
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
        ],
      );
    },
  );
}

/// The button remains mounted while its visibility changes with scroll direction.
class ScrollAwareFab extends StatelessWidget {
  const ScrollAwareFab({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedSlide(
          duration: duration,
          curve: Curves.easeOutCubic,
          offset: visible ? Offset.zero : const Offset(0, .35),
          child: AnimatedScale(
            duration: duration,
            curve: Curves.easeOutCubic,
            scale: visible ? 1 : 0,
            child: child,
          ),
        ),
      ),
    );
  }
}
