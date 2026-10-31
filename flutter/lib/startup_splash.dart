import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'recipe_store.dart';

/// Signals the Android cover only after the ready subtree has painted.
/// Keeping this outside CookdexApp leaves Windows and retained navigation alone.
class StartupReady extends StatefulWidget {
  const StartupReady({super.key, this.store, required this.child});

  final RecipeStore? store;
  final Widget child;
  static const channel = MethodChannel('com.sylph.cookdex.dev/platform');

  @override
  State<StartupReady> createState() => _StartupReadyState();
}

class _StartupReadyState extends State<StartupReady> {
  bool _scheduled = false;
  bool _sent = false;
  TimingsCallback? _timings;

  void _send(bool immediate) {
    if (_sent) return;
    _sent = true;
    if (_timings case final callback?) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
      _timings = null;
    }
    unawaited(() async {
      try {
        await StartupReady.channel.invokeMethod<void>(
          'startupReady',
          immediate,
        );
      } on MissingPluginException {
        // Host renders have no Android cover.
      } on PlatformException {
        // The native timeout still removes the cover.
      }
    }());
  }

  @override
  void dispose() {
    if (_timings case final callback?) {
      SchedulerBinding.instance.removeTimingsCallback(callback);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store ?? const _NoChanges(),
    child: widget.child,
    builder: (context, child) {
      final store = widget.store;
      final immediate =
          store == null ||
          store.error != null ||
          store.setAsideCount > 0 ||
          (!store.loading && store.summaries.isEmpty);
      if (!_sent && (immediate || (!_scheduled && !store.loading))) {
        _scheduled = true;
        if (immediate) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _send(true);
          });
        } else {
          // Listen during build, before this subtree can rasterize. Registering
          // after the frame can miss an early readiness report.
          // Timings can arrive in batches containing earlier loading frames.
          // Only the frame that built this ready subtree (or a later one) counts.
          final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
          void rasterized(List<FrameTiming> timings) {
            if (!timings.any(
              (t) =>
                  t.timestampInMicroseconds(FramePhase.vsyncStart) >=
                  frame.inMicroseconds,
            )) {
              return;
            }
            SchedulerBinding.instance.removeTimingsCallback(rasterized);
            _timings = null;
            if (mounted) _send(false);
          }

          _timings = rasterized;
          SchedulerBinding.instance.addTimingsCallback(rasterized);
        }
      }
      return child!;
    },
  );
}

class _NoChanges implements Listenable {
  const _NoChanges();
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
