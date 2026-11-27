import 'dart:async';
import 'dart:ui';

import 'package:cookdex/frame_performance_hints.dart';
import 'package:cookdex/frame_work_binding.dart';
import 'package:cookdex/immediate_frame_hint.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Immediate implements ImmediateFrameHint {
  bool live = false, fail = false;
  int opens = 0, closes = 0, increases = 0;
  final work = <int>[];
  @override
  bool start(int tid, int target) {
    expect(tid, 42);
    expect(target, greaterThan(0));
    if (!live) opens++;
    return live = true;
  }

  @override
  bool report(int nanos, int target) {
    work.add(nanos);
    return !fail;
  }

  @override
  void increase() {
    increases++;
  }

  @override
  void close() {
    if (live) closes++;
    live = false;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/frame-hints');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  FrameTiming frame(int number) => FrameTiming(
    vsyncStart: 1000,
    buildStart: 2000,
    buildFinish: 5000,
    rasterStart: 6000,
    rasterFinish: 9000,
    rasterFinishWallTime: 9000,
    frameNumber: number,
  );

  test(
    'immediate UI work is motion-only and keeps complete pipeline reports',
    () async {
      final immediate = _Immediate();
      final methods = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        methods.add(call.method);
        return call.method == 'open'
            ? 7
            : call.method == 'report'
            ? true
            : 0;
      });
      final hints = FramePerformanceHints.test(
        channel,
        () => 42,
        () => 0,
        immediateFactory: () => immediate,
      );
      await hints.setActive(true);
      expect(immediate.opens, 0);
      expect(FrameWorkReporting.onFrameWork, isNull);
      await hints.scrollWorkload(true);
      FrameWorkReporting.onFrameWork!(1000, 2000);
      FrameWorkReporting.onFrameWork!(10000, 3000);
      expect(immediate.work, [2000000, 3000000]);
      expect(immediate.opens, 1);
      await hints.scrollWorkload(true);
      expect(immediate.opens, 1);
      expect(immediate.increases, 2);
      binding.platformDispatcher.onReportTimings!([frame(1)]);
      await Future<void>.delayed(Duration.zero);
      expect(methods, contains('report'));
      await hints.scrollWorkload(false);
      expect(immediate.closes, 1);
      expect(FrameWorkReporting.onFrameWork, isNull);
      await hints.scrollWorkload(true);
      expect(immediate.opens, 2);
      await hints.setActive(false);
      expect(immediate.closes, 2);
      expect(FrameWorkReporting.onFrameWork, isNull);
      hints.dispose();
    },
  );

  test(
    'immediate failure leaves pipeline hints available and disposal detaches',
    () async {
      final immediate = _Immediate()..fail = true;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'open'
            ? 7
            : call.method == 'report'
            ? true
            : 0,
      );
      final hints = FramePerformanceHints.test(
        channel,
        () => 42,
        () => 0,
        immediateFactory: () => immediate,
      );
      await hints.setActive(true);
      await hints.scrollWorkload(true);
      FrameWorkReporting.onFrameWork!(1, 2000);
      expect(immediate.closes, 1);
      expect(FrameWorkReporting.onFrameWork, isNull);
      immediate.fail = false;
      await hints.scrollWorkload(true);
      expect(immediate.opens, 2);
      hints.dispose();
      expect(immediate.closes, 2);
      expect(FrameWorkReporting.onFrameWork, isNull);
    },
  );

  test('reports elapsed pipeline work, including queueing', () {
    expect(frameWorkNanos(frame(1)), 7000000);
  });

  test('drag and coast hints precede timings; settling resets once', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'open' ? 7 : 0;
    });
    final hints = FramePerformanceHints.test(channel, () => 42, () => 0);
    await hints.setActive(true);
    await hints.scrollWorkload(true);
    await hints.scrollWorkload(true);
    await hints.scrollWorkload(false);
    await hints.scrollWorkload(false);
    expect(calls.map((c) => c.method), [
      'open',
      'workload',
      'workload',
      'workload',
    ]);
    expect(calls.skip(1).map((c) => (c.arguments as Map)['increased']), [
      true,
      true,
      false,
    ]);
    hints.dispose();
  });

  test('scroll already underway is announced when the session opens', () async {
    final opened = Completer<Object?>();
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'open') return await opened.future;
      return call.method == 'workload' ? 0 : null;
    });
    final hints = FramePerformanceHints.test(channel, () => 42, () => 0);
    final opening = hints.setActive(true);
    await hints.scrollWorkload(true);
    opened.complete(9);
    await opening;
    await Future<void>.delayed(Duration.zero);
    expect(calls.map((c) => c.method), ['open', 'workload']);
    expect((calls.last.arguments as Map)['session'], 9);
    hints.dispose();
  });

  test('unsupported early hints preserve completed-frame reporting', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (call.method == 'open') return 2;
      if (call.method == 'workload') return 38;
      return call.method == 'report' ? true : null;
    });
    final hints = FramePerformanceHints.test(channel, () => 42, () => 0);
    await hints.setActive(true);
    await hints.scrollWorkload(true);
    binding.platformDispatcher.onReportTimings!([frame(1)]);
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['open', 'workload', 'report']);
    hints.dispose();
  });

  test('batches every completed frame and closes on pause', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'open'
          ? 7
          : call.method == 'report'
          ? true
          : null;
    });
    final hints = FramePerformanceHints.test(channel, () => 42, () => 0);
    await hints.setActive(true);
    binding.platformDispatcher.onReportTimings!([frame(1), frame(2)]);
    await Future<void>.delayed(Duration.zero);
    await hints.setActive(false);
    expect(calls.map((c) => c.method), ['open', 'report', 'close']);
    final arguments = calls[1].arguments as Map;
    expect(arguments['workNanos'], [7000000, 7000000]);
    expect(arguments['session'], 7);
    expect(arguments['targetNanos'], greaterThan(0));
    hints.dispose();
  });

  test('duplicate resume during startup does not cancel the session', () async {
    final started = Completer<Object?>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'open' ? started.future : null;
    });
    final hints = FramePerformanceHints.test(channel, () => 42, () => 0);
    final first = hints.setActive(true);
    await hints.setActive(true);
    started.complete(3);
    await first;
    await hints.setActive(false);
    expect(calls, ['open', 'close']);
    hints.dispose();
  });

  test(
    'a session completing after disposal is closed without attaching',
    () async {
      final started = Completer<Object?>();
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'open' ? started.future : null;
      });
      final hints = FramePerformanceHints.test(channel, () => 42, () => 0);
      final opening = hints.setActive(true);
      hints.dispose();
      started.complete(9);
      await opening;
      expect(calls.map((c) => c.method), ['open', 'close']);
      expect(calls.last.arguments, 9);
    },
  );

  test('an unavailable session does not register a reporter', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    final hints = FramePerformanceHints.test(channel, () => 42, () => 0);
    await hints.setActive(true);
    binding.platformDispatcher.onReportTimings?.call([frame(1)]);
    await Future<void>.delayed(Duration.zero);
    hints.dispose();
    expect(calls, ['open']);
  });

  test('resume discards the engine batch from the previous session', () async {
    final reports = <Map>[];
    var token = 0;
    var now = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'open') return ++token;
      if (call.method == 'report') {
        reports.add(call.arguments as Map);
        return true;
      }
      return null;
    });
    final hints = FramePerformanceHints.test(channel, () => 42, () => now);
    await hints.setActive(true);
    await hints.setActive(false);
    now = 10000;
    await hints.setActive(true);
    binding.platformDispatcher.onReportTimings!([
      frame(1),
      FrameTiming(
        vsyncStart: 10000,
        buildStart: 11000,
        buildFinish: 12000,
        rasterStart: 13000,
        rasterFinish: 14000,
        rasterFinishWallTime: 14000,
        frameNumber: 2,
      ),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(reports, hasLength(1));
    expect(reports.single['session'], 2);
    expect(reports.single['workNanos'], [3000000]);
    hints.dispose();
  });
}
