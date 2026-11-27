import 'dart:convert';
import 'dart:io';

import 'package:cookdex/ui/navigation_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MountCounter extends StatefulWidget {
  const _MountCounter(this.onMount);
  final VoidCallback onMount;
  @override
  State<_MountCounter> createState() => _MountCounterState();
}

class _MountCounterState extends State<_MountCounter> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => const Text('Hidden destination');
}

class _Harness {
  final controllers = [ScrollController(), ScrollController()];
  final mounts = [0, 0];
  int index = 0;
  bool ready = true, second = false;
  late StateSetter update;

  Widget list(int id) => ListView.builder(
    key: ValueKey('list-$id'),
    controller: controllers[id],
    physics: const ClampingScrollPhysics(),
    itemExtent: 53,
    itemCount: 500,
    itemBuilder: (_, row) => Text('List $id row $row'),
  );

  Future<void> mount(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final controller in controllers) {
        controller.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          scrollbars: false,
          overscroll: false,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return RetainedTabTransition(
                index: index,
                readyToWarm: ready,
                children: [
                  Column(
                    children: [
                      Expanded(child: list(0)),
                      if (second) Expanded(child: list(1)),
                    ],
                  ),
                  _MountCounter(() => mounts[0]++),
                  _MountCounter(() => mounts[1]++),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  int get hiddenMounts => mounts.reduce((a, b) => a + b);
}

void main() {
  testWidgets('hidden destinations respect a ticker-free held drag', (
    tester,
  ) async {
    final baseline =
        Platform.environment['COOKDEX_WARMUP_PROOF_ARM'] == 'baseline';
    final harness = _Harness();
    await harness.mount(tester);
    await tester.pump(const Duration(milliseconds: 240));
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('list-0'))),
    );
    await finger.moveBy(const Offset(0, -24));
    await tester.pump(const Duration(milliseconds: 16));
    await finger.moveBy(const Offset(0, -80));
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.controllers[0].offset, greaterThan(0));
    expect(harness.controllers[0].position.isScrollingNotifier.value, isTrue);
    expect(tester.binding.transientCallbackCount, 0);
    expect(harness.hiddenMounts, 0);
    await tester.pump(const Duration(milliseconds: 28));
    await tester.pump();
    expect(harness.controllers[0].position.isScrollingNotifier.value, isTrue);
    // ignore: avoid_print
    print(
      'HIDDEN_WARMUP_PAIRED ${jsonEncode({'arm': baseline ? 'baseline' : 'candidate', 'heldDrag': true, 'offset': harness.controllers[0].offset, 'transientCallbacks': tester.binding.transientCallbackCount, 'hiddenMounts': harness.hiddenMounts})}',
    );
    expect(harness.hiddenMounts, baseline ? greaterThan(0) : 0);
    if (!baseline) {
      expect(
        tester.binding.hasScheduledFrame,
        isFalse,
        reason: 'Parked warm-up must not generate its own animation frames.',
      );
    }
    await finger.cancel();
    await tester.pumpAndSettle();
    expect(harness.hiddenMounts, 2);
  });

  testWidgets('stationary pointer holds warm-up and cancellation resumes it', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.mount(tester);
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('list-0'))),
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(harness.hiddenMounts, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await finger.cancel();
    await tester.pumpAndSettle();
    expect(harness.hiddenMounts, 2);
  });

  testWidgets(
    'readiness cancellation preserves the delay without parallel warm-up',
    (tester) async {
      final harness = _Harness();
      await harness.mount(tester);
      await tester.pump(const Duration(milliseconds: 200));
      harness.update(() => harness.ready = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(harness.hiddenMounts, 0);
      harness.update(() => harness.ready = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      harness.update(() => harness.ready = false);
      await tester.pump();
      harness.update(() => harness.ready = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 299));
      expect(harness.hiddenMounts, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(
        harness.hiddenMounts,
        1,
        reason: 'Only one hidden destination may be mounted in a frame.',
      );
      await tester.pumpAndSettle();
      expect(harness.hiddenMounts, 2);
    },
  );

  testWidgets(
    'independent scrolls and a disposed activity cannot release or strand warming',
    (tester) async {
      final harness = _Harness()..second = true;
      await harness.mount(tester);
      await tester.pump(const Duration(milliseconds: 240));
      final first = harness.controllers[0].position.drag(
        DragStartDetails(),
        () {},
      );
      harness.controllers[1].position.drag(DragStartDetails(), () {});
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(harness.hiddenMounts, 0);
      harness.update(() => harness.second = false);
      await tester.pump();
      expect(harness.controllers[1].hasClients, isFalse);
      expect(harness.controllers[0].position.isScrollingNotifier.value, isTrue);
      expect(
        harness.hiddenMounts,
        0,
        reason: 'Disposing one activity does not end the other activity.',
      );
      first.cancel();
      await tester.pumpAndSettle();
      expect(
        harness.hiddenMounts,
        2,
        reason: 'The disposed scroller must not leave a stale busy entry.',
      );
    },
  );

  testWidgets(
    'selection mounts immediately and outgoing activity does not block new tab',
    (tester) async {
      final harness = _Harness();
      await harness.mount(tester);
      await tester.pump(const Duration(milliseconds: 240));
      final drag = harness.controllers[0].position.drag(
        DragStartDetails(),
        () {},
      );
      harness.update(() => harness.index = 1);
      await tester.pump();
      expect(
        harness.mounts[0],
        1,
        reason: 'An explicitly selected destination never waits for warm-up.',
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(harness.controllers[0].position.isScrollingNotifier.value, isTrue);
      expect(
        harness.mounts[1],
        1,
        reason: 'A retained outgoing activity must not block the current tab.',
      );
      drag.cancel();
    },
  );

  testWidgets(
    'an activity spanning readiness remains gated and disposal releases it',
    (tester) async {
      final harness = _Harness()
        ..ready = false
        ..second = true;
      await harness.mount(tester);
      harness.controllers[1].position.drag(DragStartDetails(), () {});
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.hiddenMounts, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      harness.update(() => harness.ready = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(
        harness.hiddenMounts,
        0,
        reason: 'Readiness must not forget a pre-existing active scroll.',
      );
      harness.update(() => harness.second = false);
      await tester.pump();
      expect(harness.controllers[1].hasClients, isFalse);
      await tester.pumpAndSettle();
      expect(harness.hiddenMounts, 2);
    },
  );
}
