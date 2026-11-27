import 'dart:ffi';

/// A separate UI-only session: elapsed UI work is never passed off as a finished
/// UI/raster/GPU pipeline. The existing pipeline session keeps its own timings.
abstract interface class ImmediateFrameHint {
  bool start(int uiTid, int targetNanos);
  bool report(int workNanos, int targetNanos);
  void increase();
  void close();
}

class NativeImmediateFrameHint implements ImmediateFrameHint {
  NativeImmediateFrameHint._(DynamicLibrary library)
    : _open = library
          .lookupFunction<Int64 Function(Int32, Int64), int Function(int, int)>(
            'cookdex_ui_hint_open',
          ),
      _report = library
          .lookupFunction<
            Int32 Function(Int64, Int64, Int64),
            int Function(int, int, int)
          >('cookdex_ui_hint_report'),
      _increase = library
          .lookupFunction<Int32 Function(Int64), int Function(int)>(
            'cookdex_ui_hint_increase',
          ),
      _close = library.lookupFunction<Void Function(Int64), void Function(int)>(
        'cookdex_ui_hint_close',
      );

  static ImmediateFrameHint? load() {
    try {
      return NativeImmediateFrameHint._(
        DynamicLibrary.open('libcookdex_bridge.so'),
      );
    } catch (_) {
      return null;
    }
  }

  final int Function(int, int) _open;
  final int Function(int, int, int) _report;
  final int Function(int) _increase;
  final void Function(int) _close;
  int _token = 0;

  @override
  bool start(int uiTid, int targetNanos) {
    if (_token == 0) _token = _open(uiTid, targetNanos);
    return _token != 0;
  }

  @override
  bool report(int workNanos, int targetNanos) =>
      _token != 0 && _report(_token, workNanos, targetNanos) == 0;

  @override
  void increase() {
    if (_token != 0) _increase(_token);
  }

  @override
  void close() {
    final token = _token;
    _token = 0;
    if (token != 0) _close(token);
  }
}
