import 'dart:async';

import 'package:flutter/foundation.dart';

/// Coalesces optional work until pointer contact and scrolling have both ended.
/// Work already started is never cancelled. Explicit searches remain immediate.
class InteractionIdle {
  static final instance = InteractionIdle();
  @visibleForTesting
  static void Function(String name, bool starting)? debugWork;

  static void synchronous(String name, VoidCallback work) {
    debugWork?.call(name, true);
    try {
      work();
    } finally {
      debugWork?.call(name, false);
    }
  }

  static Future<T> asynchronous<T>(
    String name,
    Future<T> Function() work,
  ) async {
    debugWork?.call(name, true);
    try {
      return await work();
    } finally {
      debugWork?.call(name, false);
    }
  }

  final _busy = <Object>{};
  final _waiting = <Object, VoidCallback>{};
  Timer? _wake;

  bool get busy => _busy.isNotEmpty;

  void hold(Object owner, bool held) {
    if (held) {
      _busy.add(owner);
    } else {
      _busy.remove(owner);
      _schedule();
    }
  }

  void runWhenIdle(Object key, VoidCallback work) {
    if (!busy && _waiting.isEmpty) {
      work();
      return;
    }
    _waiting[key] = work;
    _schedule();
  }

  Future<void> get idle {
    if (!busy) return Future.value();
    final completion = Completer<void>();
    runWhenIdle(completion, completion.complete);
    return completion.future;
  }

  void cancel(Object key) => _waiting.remove(key);

  void _schedule() {
    if (busy || _wake != null || _waiting.isEmpty) return;
    _wake = Timer(Duration.zero, () {
      _wake = null;
      if (busy || _waiting.isEmpty) return;
      final key = _waiting.keys.first;
      final work = _waiting.remove(key)!;
      try {
        work();
      } finally {
        _schedule();
      }
    });
  }
}
