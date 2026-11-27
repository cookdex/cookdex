import 'dart:async';

/// Keeps the trailing 180 ms minimum quiet period with one pending timer.
/// The caller owns snapshot serialization and error handling.
class DebouncedPreferenceWrite {
  DebouncedPreferenceWrite(this._write, {this.nowMicroseconds});

  static const _quietUs = 180000;
  final Future<void> Function() _write;
  final int Function()? nowMicroseconds;
  late final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  int _deadlineUs = 0;

  int get _nowUs => nowMicroseconds?.call() ?? _clock.elapsedMicroseconds;

  void schedule() {
    _deadlineUs = _nowUs + _quietUs;
    _timer ??= Timer(const Duration(milliseconds: 180), _onTimer);
  }

  void _onTimer() {
    _timer = null;
    final remainingUs = _deadlineUs - _nowUs;
    if (remainingUs > 0) {
      // Timer uses millisecond granularity. Rounding down could create a
      // zero-delay retry loop during the last fractional millisecond.
      _timer = Timer(
        Duration(milliseconds: (remainingUs + 999) ~/ 1000),
        _onTimer,
      );
    } else {
      unawaited(flush());
    }
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _deadlineUs = 0;
    return _write();
  }

  /// Disposal preserves the latest state through the existing write callback.
  Future<void> dispose() => flush();
}
