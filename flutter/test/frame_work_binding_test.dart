import 'dart:async';
import 'dart:developer' as developer;

import 'package:cookdex/frame_work_binding.dart';
import 'package:cookdex/frame_performance_hints.dart';
import 'package:cookdex/immediate_frame_hint.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding
    with FrameWorkReporting {}

class _Hint implements ImmediateFrameHint {
  final events = <String>[];
  @override
  bool start(int ui, int target) {
    events.add('open');
    return true;
  }

  @override
  bool report(int work, int target) {
    expect(work, greaterThan(0));
    events.add('report');
    return true;
  }

  @override
  void increase() {}
  @override
  void close() {
    events.add('close');
  }
}

void main() {
  final binding = _Binding();
  tearDown(() => FrameWorkReporting.onFrameWork = null);

  testWidgets(
    'UI timing includes animation and post-frame work without pumping idle',
    (tester) async {
      final reports = <(int, int)>[];
      int animation = 0, post = 0;
      expect(binding.currentFrameStartUs, isNull);
      FrameWorkReporting.onFrameWork = (start, elapsed) =>
          reports.add((start, elapsed));
      binding.scheduleFrameCallback((_) {
        animation = developer.Timeline.now;
        expect(binding.currentFrameStartUs, lessThanOrEqualTo(animation));
      });
      binding.addPostFrameCallback((_) => post = developer.Timeline.now);
      await tester.pumpWidget(const SizedBox());
      expect(reports, hasLength(1));
      expect(reports.single.$1, lessThanOrEqualTo(animation));
      expect(reports.single.$1 + reports.single.$2, greaterThanOrEqualTo(post));
      expect(binding.currentFrameStartUs, isNull);
      expect(binding.hasScheduledFrame, isFalse);
      await tester.idle();
      expect(reports, hasLength(1));
    },
  );

  for (final transient in [false, true]) {
    testWidgets(
      'settle reports before close, including transient callbacks: $transient',
      (tester) async {
        const channel = MethodChannel('test/ui-final-frame');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'open' ? 1 : 0,
        );
        final native = _Hint();
        final hints = FramePerformanceHints.test(
          channel,
          () => 42,
          () => 0,
          immediateFactory: () => native,
        );
        await hints.setActive(true);
        await hints.scrollWorkload(true);
        if (transient) {
          binding.scheduleFrameCallback(
            (_) => unawaited(hints.scrollWorkload(false)),
          );
        } else {
          binding.addPostFrameCallback(
            (_) => unawaited(hints.scrollWorkload(false)),
          );
        }
        await tester.pumpWidget(const SizedBox());
        expect(native.events, ['open', 'report', 'close']);
        expect(FrameWorkReporting.onFrameWork, isNull);
        expect(binding.hasScheduledFrame, isFalse);
        hints.dispose();
        await tester.idle();
        messenger.setMockMethodCallHandler(channel, null);
      },
    );
  }

  testWidgets('a session ended during the frame never receives stale work', (
    tester,
  ) async {
    var calls = 0;
    FrameWorkReporting.onFrameWork = (_, _) => calls++;
    binding.addPostFrameCallback((_) => FrameWorkReporting.onFrameWork = null);
    await tester.pumpWidget(const SizedBox());
    expect(calls, 0);
  });
}
