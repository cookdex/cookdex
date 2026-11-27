import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

typedef UiFrameWork = void Function(int startUs, int elapsedUs);

/// Measures only the UI frame, from animation callbacks through post-frame work.
/// It observes natural frames; it never schedules a frame or estimates GPU work.
mixin FrameWorkReporting on WidgetsBinding {
  static UiFrameWork? onFrameWork;
  static UiFrameWork? _pendingReceiver;
  static bool isMeasuring(UiFrameWork receiver) =>
      identical(_pendingReceiver, receiver);
  UiFrameWork? _frameReceiver;
  int _frameStartUs = 0;

  /// The already-measured live frame, including earlier animation callbacks.
  /// Null when immediate reporting is inactive; reading it starts no work.
  int? get currentFrameStartUs => _frameReceiver == null ? null : _frameStartUs;

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _frameReceiver = onFrameWork;
    _pendingReceiver = _frameReceiver;
    if (_frameReceiver != null) _frameStartUs = developer.Timeline.now;
    super.handleBeginFrame(rawTimeStamp);
  }

  @override
  void handleDrawFrame() {
    try {
      super.handleDrawFrame();
    } finally {
      final receiver = _frameReceiver;
      _frameReceiver = null;
      try {
        if (receiver != null && identical(receiver, onFrameWork)) {
          receiver(_frameStartUs, developer.Timeline.now - _frameStartUs);
        }
      } finally {
        _pendingReceiver = null;
      }
    }
  }
}

class CookdexBinding extends WidgetsFlutterBinding with FrameWorkReporting {}
