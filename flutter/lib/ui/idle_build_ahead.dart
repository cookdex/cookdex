import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Expands only the layout cache, after the visible frame/route transition.
/// Scroll input immediately returns to Flutter's normal on-demand cache.
class IdleBuildAhead extends StatefulWidget {
  const IdleBuildAhead({
    super.key,
    required this.builder,
    this.allRows = false,
    this.enabled = true,
    this.axis = Axis.vertical,
    this.initialCache = 250,
    this.paused,
    this.controller,
  });
  final Widget Function(BuildContext, double) builder;
  final bool allRows, enabled;
  final Axis axis;
  final double initialCache;
  final ValueListenable<bool>? paused;
  final ScrollController? controller;

  @override
  State<IdleBuildAhead> createState() => _IdleBuildAheadState();
}

class _IdleBuildAheadState extends State<IdleBuildAhead> {
  late double _cache = widget.initialCache;
  ScrollMetrics? _metrics;
  Animation<double>? _route;
  int? _frame;
  bool _visible = true, _scrolling = false, _contact = false;
  int _lastBuildUs = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    widget.paused?.addListener(_pauseChanged);
  }

  void _timings(List<FrameTiming> values) {
    if (values.isNotEmpty) {
      _lastBuildUs = values.last.buildDuration.inMicroseconds;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    final route = ModalRoute.of(context)?.animation;
    if (!identical(route, _route)) {
      _route?.removeStatusListener(_transition);
      _route = route;
      _route?.addStatusListener(_transition);
    }
    _queue();
  }

  @override
  void didUpdateWidget(IdleBuildAhead oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) {
      oldWidget.paused?.removeListener(_pauseChanged);
      widget.paused?.addListener(_pauseChanged);
    }
    if (!widget.enabled) _cache = widget.initialCache;
    _queue();
  }

  void _transition(AnimationStatus _) => _queue();

  void _pauseChanged() {
    if (widget.paused?.value == true && _frame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
      _frame = null;
    }
    _queue();
  }

  double get _target {
    final metrics = _metrics;
    if (metrics == null) return widget.initialCache;
    return widget.allRows
        ? metrics.maxScrollExtent + metrics.viewportDimension
        : math.min(
            metrics.viewportDimension * 2,
            metrics.maxScrollExtent + metrics.viewportDimension,
          );
  }

  bool get _canBuild =>
      widget.enabled &&
      widget.paused?.value != true &&
      _visible &&
      !_scrolling &&
      !_contact &&
      (_route == null || _route!.status == AnimationStatus.completed) &&
      _cache < _target;

  void _queue() {
    if (_frame != null || !mounted || !_canBuild) return;
    _frame = SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      if (!mounted || !_canBuild) return;
      // ScrollEnd is dispatched before the position changes its activity.
      // Check the live position at execution, not only cached notifications.
      if (widget.controller?.hasClients == true &&
          widget.controller!.position.isScrollingNotifier.value) {
        return;
      }
      final hz = View.of(context).display.refreshRate;
      final budget = 1000000 / (hz > 0 ? hz : 60);
      // One small band per frame. Expensive recent builds reduce the band;
      // existing children keep their elements and render objects.
      final step = _lastBuildUs > budget * .7 ? 32.0 : 96.0;
      setState(() => _cache = math.min(_target, _cache + step));
      _queue();
    });
  }

  @override
  void dispose() {
    if (_frame case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    _route?.removeStatusListener(_transition);
    widget.paused?.removeListener(_pauseChanged);
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _contact = true,
    onPointerUp: (_) {
      _contact = false;
      _queue();
    },
    onPointerCancel: (_) {
      _contact = false;
      _queue();
    },
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == widget.axis) {
          _metrics = notification.metrics;
          _queue();
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0 ||
              notification.metrics.axis != widget.axis) {
            return false;
          }
          _metrics = notification.metrics;
          if (notification is ScrollStartNotification) {
            _scrolling = true;
            if (_cache != widget.initialCache) {
              setState(() => _cache = widget.initialCache);
            }
          } else if (notification is ScrollEndNotification) {
            _scrolling = false;
            _queue();
          }
          return false;
        },
        child: widget.builder(context, _cache),
      ),
    ),
  );
}

/// Bounds retained Cards by recipe count, including grid rows. Visible children
/// remain live normally even after their retention allowance is released.
class BuiltRowBudget {
  @visibleForTesting
  static void Function(int)? debugRetained;
  BuiltRowBudget(this.capacity);
  final int capacity;
  final _rows = <_KeepBuiltState, int>{};
  int _weight = 0;

  void _retain(_KeepBuiltState row, int weight) {
    _remove(row);
    _rows[row] = weight;
    _weight += weight;
    row._retain(true);
    while (_weight > capacity && _rows.isNotEmpty) {
      final oldest = _rows.keys.first;
      _remove(oldest);
      oldest._retain(false);
    }
    debugRetained?.call(_weight);
  }

  void _remove(_KeepBuiltState row) => _weight -= _rows.remove(row) ?? 0;
}

class KeepBuilt extends StatefulWidget {
  const KeepBuilt({
    super.key,
    required this.child,
    this.budget,
    this.weight = 1,
    this.enabled = true,
  });
  final Widget child;
  final BuiltRowBudget? budget;
  final int weight;
  final bool enabled;
  @override
  State<KeepBuilt> createState() => _KeepBuiltState();
}

class _KeepBuiltState extends State<KeepBuilt>
    with AutomaticKeepAliveClientMixin {
  bool _kept = true;
  @override
  bool get wantKeepAlive => _kept && widget.enabled;
  void _retain(bool value) {
    if (_kept == value) return;
    _kept = value;
    if (value) {
      updateKeepAlive();
    } else {
      // A wide viewport can exceed the retention budget in its first layout.
      // Let AutomaticKeepAlive attach its initial parent data before releasing
      // that handle; releasing it during the same layout races its callback.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_kept) updateKeepAlive();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    widget.budget?._retain(this, widget.weight);
    updateKeepAlive();
  }

  @override
  void didUpdateWidget(KeepBuilt oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.budget?._remove(this);
    _retain(true);
    widget.budget?._retain(this, widget.weight);
    updateKeepAlive();
  }

  @override
  void dispose() {
    widget.budget?._remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class BuiltSliverList extends StatelessWidget {
  const BuiltSliverList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SliverList.list(
    children: [
      for (final (index, child) in children.indexed)
        KeepBuilt(
          key: ValueKey(('built-row', child.key ?? index)),
          child: child,
        ),
    ],
  );
}
