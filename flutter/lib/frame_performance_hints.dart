import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ffi';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'frame_work_binding.dart';
import 'immediate_frame_hint.dart';

/// Elapsed frame-pipeline work, including scheduling/queueing, not CPU time.
@visibleForTesting
int frameWorkNanos(FrameTiming timing) =>
    (timing.timestampInMicroseconds(FramePhase.rasterFinish) -
        timing.timestampInMicroseconds(FramePhase.buildStart)) *
    1000;

/// Android's optional scheduler feedback. Flutter delivers these measurements
/// in batches; callers must not treat this as immediate raster-completion data.
class FramePerformanceHints {
  FramePerformanceHints()
    : _supported = Platform.isAndroid,
      _channel = const MethodChannel('com.sylph.cookdex.dev/frame-hints'),
      _uiThreadId = _nativeThreadId,
      _clock = (() => developer.Timeline.now),
      _immediateFactory = NativeImmediateFrameHint.load;

  @visibleForTesting
  FramePerformanceHints.test(
    this._channel,
    this._uiThreadId,
    this._clock, {
    ImmediateFrameHint? Function()? immediateFactory,
  }) : _supported = true,
       _immediateFactory = immediateFactory ?? (() => null);

  final bool _supported;
  final MethodChannel _channel;
  final int Function() _uiThreadId;
  final int Function() _clock;
  final ImmediateFrameHint? Function() _immediateFactory;
  ImmediateFrameHint? _immediate;
  bool _finishingUiFrame = false;
  late final UiFrameWork _uiReporter = _uiFrame;
  int _activeSinceUs = 0;

  void _uiFrame(int startUs, int elapsedUs) {
    if (!_active || (!_scrolling && !_finishingUiFrame) || elapsedUs <= 0) {
      return;
    }
    if (_immediate?.report(elapsedUs * 1000, _budget()) != true ||
        !_scrolling) {
      _stopImmediate();
    }
  }

  void _stopImmediate() {
    _finishingUiFrame = false;
    if (identical(FrameWorkReporting.onFrameWork, _uiReporter)) {
      FrameWorkReporting.onFrameWork = null;
    }
    _immediate?.close();
  }

  void _startImmediate() {
    if (!_active || !_scrolling) return;
    _finishingUiFrame = false;
    _immediate ??= _immediateFactory();
    if (_immediate?.start(_uiThreadId(), _budget()) == true) {
      FrameWorkReporting.onFrameWork = _uiReporter;
      _immediate!.increase();
    }
  }

  static int _nativeThreadId() =>
      DynamicLibrary.open('libc.so')
          .lookupFunction<Int32 Function(), int Function()>('gettid')();
  int _generation = 0;
  int? _session;
  bool _listening = false, _disposed = false, _starting = false;
  bool _active = false;
  bool _scrolling = false;
  final _pending = <int>[];
  bool _sending = false;

  Future<void> setActive(bool active) async {
    if (_disposed || !_supported) return;
    if (active == _active && (_starting || _session != null)) return;
    _active = active;
    final generation = ++_generation;
    if (!active) {
      _stopImmediate();
      _detach();
      final session = _session;
      _session = null;
      if (session != null) {
        try {
          await _channel.invokeMethod<void>('close', session);
        } on PlatformException {
          // Scheduler hints are optional and never block application lifecycle.
        } on MissingPluginException {
          // Unsupported hosts keep the ordinary scheduler behavior.
        }
      }
      return;
    }
    if (_session != null || _starting) return;
    _starting = true;
    try {
      final session = await _channel.invokeMethod<int>('open', {
        'uiTid': _uiThreadId(),
        'targetNanos': _budget(),
      });
      if (_disposed || generation != _generation) {
        if (session != null) {
          await _channel.invokeMethod<void>('close', session);
        }
        return;
      }
      _session = session;
      if (session != null) {
        _activeSinceUs = _clock();
        SchedulerBinding.instance.addTimingsCallback(_timings);
        _listening = true;
        if (_scrolling) unawaited(scrollWorkload(true));
      }
    } catch (_) {
      // Missing APIs, ambiguous engine threads and unsupported devices are safe
      // no-ops. They must never affect the app's ability to open or scroll.
    } finally {
      _starting = false;
      if (!_disposed &&
          _active &&
          generation != _generation &&
          _session == null) {
        unawaited(setActive(true));
      }
    }
  }

  int _budget() {
    final rate =
        PlatformDispatcher.instance.views.firstOrNull?.display.refreshRate;
    return (1000000000 / (rate != null && rate > 0 ? rate : 60)).round();
  }

  /// Announces changes before the next frame, rather than waiting for its
  /// batched timing report. A drag-to-fling transition is another increase.
  Future<void> scrollWorkload(bool increased) async {
    if (_disposed || !_supported) return;
    if (!increased && !_scrolling) return;
    _scrolling = increased;
    if (increased) {
      _startImmediate();
    } else if (FrameWorkReporting.isMeasuring(_uiReporter)) {
      // ScrollEnd can occur in this frame's layout/post-frame callbacks. Report
      // its complete UI work before closing, without scheduling another frame.
      _finishingUiFrame = true;
    } else {
      _stopImmediate();
    }
    final session = _session;
    if (session == null) return;
    try {
      await _channel.invokeMethod<int>('workload', {
        'session': session,
        'increased': increased,
      });
    } on PlatformException {
      // An optional workload hint cannot disable ordinary frame reporting.
    } on MissingPluginException {
      // Older platforms still use the existing completed-frame hints.
    }
  }

  void _timings(List<FrameTiming> timings) {
    if (_session == null || _disposed) return;
    for (final timing in timings) {
      // The engine retains batched timings across callback detachment. Work
      // measured before this session opened cannot describe its workload.
      if (timing.timestampInMicroseconds(FramePhase.buildStart) <
          _activeSinceUs) {
        continue;
      }
      final work = frameWorkNanos(timing);
      if (work > 0) _pending.add(work);
    }
    // Bound backpressure if a platform handler stops answering. Never allow
    // a stalled optional service to accumulate frames for the whole session.
    if (_pending.length > 200) {
      unawaited(setActive(false));
      return;
    }
    unawaited(_send());
  }

  Future<void> _send() async {
    if (_sending || _pending.isEmpty || _session == null) return;
    _sending = true;
    final session = _session!;
    final values = Int64List.fromList(_pending);
    _pending.clear();
    try {
      final accepted = await _channel.invokeMethod<bool>('report', {
        'session': session,
        'targetNanos': _budget(),
        'workNanos': values,
      });
      if (accepted != true && _session == session) {
        await setActive(false);
      }
    } on PlatformException {
      if (_session == session) await setActive(false);
    } on MissingPluginException {
      if (_session == session) await setActive(false);
    } finally {
      _sending = false;
      if (!_disposed && _session != null && _pending.isNotEmpty) {
        unawaited(_send());
      }
    }
  }

  void _detach() {
    if (_listening) SchedulerBinding.instance.removeTimingsCallback(_timings);
    _listening = false;
    _pending.clear();
  }

  void dispose() {
    if (_disposed) return;
    unawaited(setActive(false));
    _disposed = true;
  }
}
