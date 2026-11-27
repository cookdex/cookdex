import 'dart:async';

import 'package:flutter/widgets.dart';

import '../interaction_idle.dart';

/// Observes input without entering its gesture arena or changing hit testing.
class InteractionIdleScope extends StatefulWidget {
  const InteractionIdleScope({
    super.key,
    required this.child,
    this.onScrollWorkload,
  });
  final Widget child;
  final ValueChanged<bool>? onScrollWorkload;
  @override
  State<InteractionIdleScope> createState() => _InteractionIdleScopeState();
}

class _InteractionIdleScopeState extends State<InteractionIdleScope> {
  final _contacts = <int>{};
  final _scrolling = <WeakReference<ScrollableState>>[];
  bool _checking = false;
  bool _workloadActive = false;
  final _idle = InteractionIdle.instance;

  void _update() {
    _scrolling.removeWhere((entry) {
      final state = entry.target;
      return state == null ||
          !state.mounted ||
          !state.position.isScrollingNotifier.value;
    });
    _idle.hold(this, _contacts.isNotEmpty || _scrolling.isNotEmpty);
    if (_scrolling.isEmpty && _contacts.isEmpty && _workloadActive) {
      _workloadActive = false;
      widget.onScrollWorkload?.call(false);
    }
    if (_scrolling.isNotEmpty && !_checking) {
      _checking = true;
      // Follow natural frames only; never generate frames for this observer.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checking = false;
        if (mounted) _update();
      });
    }
  }

  bool _scroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      final context = notification.context;
      final state = context == null ? null : Scrollable.maybeOf(context);
      if (state != null && !_scrolling.any((e) => identical(e.target, state))) {
        _scrolling.add(WeakReference(state));
      }
      // ScrollStart can precede the notifier update; hold through this event.
      _idle.hold(this, true);
      _workloadActive = true;
      widget.onScrollWorkload?.call(true);
      if (!_checking) {
        _checking = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checking = false;
          if (mounted) _update();
        });
      }
    } else if (notification is ScrollEndNotification) {
      final context = notification.context;
      final state = context == null ? null : Scrollable.maybeOf(context);
      _scrolling.removeWhere((entry) => identical(entry.target, state));
      _update();
    }
    return false;
  }

  @override
  void dispose() {
    _idle.hold(this, false);
    if (_workloadActive) widget.onScrollWorkload?.call(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      _contacts.add(event.pointer);
      _workloadActive = true;
      widget.onScrollWorkload?.call(true);
      _update();
    },
    onPointerUp: (event) {
      _contacts.remove(event.pointer);
      _update();
      // Pointer routing finishes the drag and starts the ballistic activity
      // after this Listener runs. A microtask observes that transition before
      // its first frame, without reading protected ScrollActivity state.
      scheduleMicrotask(() {
        if (!mounted || _contacts.isNotEmpty) return;
        _update();
        if (_workloadActive) widget.onScrollWorkload?.call(true);
      });
    },
    onPointerCancel: (event) {
      _contacts.remove(event.pointer);
      _update();
    },
    child: NotificationListener<ScrollNotification>(
      onNotification: _scroll,
      child: widget.child,
    ),
  );
}
