import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Android phones stay upright; larger current displays follow the system.
class PhoneOrientation extends StatefulWidget {
  const PhoneOrientation({
    super.key,
    required this.isAndroid,
    required this.child,
  });

  final bool isAndroid;
  final Widget child;

  @override
  State<PhoneOrientation> createState() => _PhoneOrientationState();
}

class _PhoneOrientationState extends State<PhoneOrientation>
    with WidgetsBindingObserver {
  ui.FlutterView? _view;
  bool? _portrait;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _view = View.maybeOf(context);
    _updateOrientation();
  }

  @override
  void didUpdateWidget(PhoneOrientation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAndroid != widget.isAndroid) {
      _portrait = null;
      _updateOrientation();
    }
  }

  @override
  void didChangeMetrics() => _updateOrientation();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _updateOrientation();
  }

  void _updateOrientation() {
    if (!widget.isAndroid) return;
    final display = _view?.display;
    if (display == null ||
        display.devicePixelRatio <= 0 ||
        display.size.isEmpty) {
      return;
    }
    // The window can be letterboxed or split-screen. Use the actual current
    // display so unfolding releases a phone lock even before the window grows.
    final portrait = display.size.shortestSide / display.devicePixelRatio < 600;
    if (_portrait == portrait) return;
    _portrait = portrait;
    unawaited(
      SystemChrome.setPreferredOrientations(
        portrait ? const [DeviceOrientation.portraitUp] : const [],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _view = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
