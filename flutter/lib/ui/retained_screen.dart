import 'package:flutter/material.dart';

/// Retain a hidden route/tab's last viewport until it becomes visible again.
/// Keyboard animation must not invalidate every retained screen underneath it.
/// Repository notifications still reach those screens normally.
class RetainedScreen extends StatefulWidget {
  const RetainedScreen({super.key, required this.child, this.visible = true});
  final Widget child;
  final bool visible;
  @override
  State<RetainedScreen> createState() => _RetainedScreenState();
}

class _RetainedScreenState extends State<RetainedScreen> {
  MediaQueryData? _lastVisible;
  Widget? _lastVisibleChild;
  @override
  Widget build(BuildContext context) {
    final current = MediaQuery.of(context);
    final visible =
        widget.visible &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    if (visible || _lastVisible == null) {
      _lastVisible = current;
      _lastVisibleChild = widget.child;
    }
    return MediaQuery(data: _lastVisible!, child: _lastVisibleChild!);
  }
}

/// Only a visible status widget listens to UI status polling. On reveal it
/// reads current state, so no stale indicator or hidden polling build is needed.
class VisibleListenableBuilder extends StatefulWidget {
  const VisibleListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
  });
  final Listenable? listenable;
  final WidgetBuilder builder;
  @override
  State<VisibleListenableBuilder> createState() =>
      _VisibleListenableBuilderState();
}

class _VisibleListenableBuilderState extends State<VisibleListenableBuilder> {
  Listenable? _listening;
  void _changed() => setState(() {});
  void _update() {
    final next =
        TickerMode.valuesOf(context).enabled &&
            (ModalRoute.isCurrentOf(context) ?? true)
        ? widget.listenable
        : null;
    if (identical(next, _listening)) return;
    _listening?.removeListener(_changed);
    _listening = next;
    _listening?.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(VisibleListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _listening?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
