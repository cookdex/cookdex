import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookdex/debounced_preference_write.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

class _ManualTimer implements Timer {
  _ManualTimer(this.deadline, this.callback);
  final int deadline;
  final void Function() callback;
  bool _active = true;
  int _tick = 0;
  @override
  bool get isActive => _active;
  @override
  int get tick => _tick;
  @override
  void cancel() => _active = false;
  void fire() {
    if (!_active) return;
    _active = false;
    _tick = 1;
    callback();
  }
}

class _Time {
  int now = 0, created = 0, peakPending = 0;
  final timers = <_ManualTimer>[];
  int get pending => timers.where((timer) => timer.isActive).length;
  T run<T>(T Function() body) => runZoned(
    body,
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        expect(
          duration.inMicroseconds,
          greaterThan(0),
          reason: 'No zero-delay retry loop is allowed.',
        );
        final timer = _ManualTimer(now + duration.inMicroseconds, callback);
        timers.add(timer);
        created++;
        if (pending > peakPending) peakPending = pending;
        return timer;
      },
    ),
  );
  void elapse(int microseconds) {
    final target = now + microseconds;
    var callbacks = 0;
    while (true) {
      final due =
          timers
              .where((timer) => timer.isActive && timer.deadline <= target)
              .toList()
            ..sort((a, b) => a.deadline.compareTo(b.deadline));
      if (due.isEmpty) break;
      if (++callbacks > 2000) throw StateError('Timer retry loop');
      now = due.first.deadline;
      due.first.fire();
    }
    now = target;
  }
}

void main() {
  test(
    'continuous changes defer writing and allocate bounded timers',
    () async {
      final time = _Time();
      var value = 0;
      final writes = <(int, int)>[];
      final writer = DebouncedPreferenceWrite(() async {
        writes.add((time.now, value));
      }, nowMicroseconds: () => time.now);
      time.run(() {
        for (var i = 0; i < 1200; i++) {
          value = i;
          writer.schedule();
          if (i < 1199) time.elapse(8333);
        }
        final lastEdit = time.now;
        expect(writes, isEmpty);
        expect(time.pending, 1);
        expect(
          time.created,
          lessThan(70),
          reason: 'One timer per offset would create 1200 timers.',
        );
        expect(time.peakPending, 1);
        time.elapse(179999);
        expect(writes, isEmpty);
        time.elapse(1001);
        expect(writes, hasLength(1));
        expect(writes.single.$2, 1199);
        expect(
          writes.single.$1,
          inInclusiveRange(lastEdit + 180000, lastEdit + 180999),
        );
        expect(time.pending, 0);
      });
    },
  );

  test(
    'fractional remaining time rounds up without early write or busy retry',
    () {
      final time = _Time();
      final writes = <int>[];
      final writer = DebouncedPreferenceWrite(() async {
        writes.add(time.now);
      }, nowMicroseconds: () => time.now);
      time.run(() {
        writer.schedule();
        time.elapse(125);
        writer.schedule();
        time.elapse(179875);
        expect(writes, isEmpty);
        expect(time.created, 2);
        time.elapse(999);
        expect(writes, isEmpty);
        time.elapse(1);
        expect(writes, [181000]);
        expect(time.pending, 0);
      });
    },
  );

  test(
    'explicit flush cancels the deadline and later changes write normally',
    () async {
      final time = _Time();
      var value = 1;
      final writes = <int>[];
      final writer = DebouncedPreferenceWrite(() async {
        writes.add(value);
      }, nowMicroseconds: () => time.now);
      await time.run(() async {
        writer.schedule();
        time.elapse(100000);
        await writer.flush();
        expect(time.pending, 0);
        expect(writes, [1]);
        time.elapse(200000);
        expect(writes, [1]);
        value = 2;
        writer.schedule();
        time.elapse(180000);
        expect(writes, [1, 2]);
        expect(time.pending, 0);
      });
    },
  );

  test(
    'disposal flushes once and leaves no later scheduled callback',
    () async {
      final time = _Time();
      var calls = 0;
      final writer = DebouncedPreferenceWrite(() async {
        calls++;
      }, nowMicroseconds: () => time.now);
      await time.run(() async {
        writer.schedule();
        time.elapse(179000);
        await writer.dispose();
        expect(calls, 1);
        expect(time.pending, 0);
        time.elapse(1000000);
        expect(calls, 1);
      });
    },
  );

  test(
    'flush returns the actual write completion and does not swallow failure',
    () async {
      final pending = Completer<void>();
      final writer = DebouncedPreferenceWrite(() => pending.future);
      final result = writer.flush();
      expect(result, same(pending.future));
      final failure = expectLater(result, throwsStateError);
      pending.completeError(StateError('controlled write failure'));
      await failure;
    },
  );

  test('real preferences preserve serialized snapshots and latest offset', () async {
    final directory = await Directory.systemTemp.createTemp(
      'cookdex-write-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/preferences.json');
    final preferences = await LocalPreferences.load(file.path);
    preferences.setScrollOffset(10);
    final first = preferences.flush();
    preferences.setScrollOffset(20);
    final second = preferences.flush();
    await Future.wait([first, second]);
    expect((jsonDecode(await file.readAsString()) as Map)['scrollOffset'], 20);
    preferences.setScrollOffset(30);
    preferences.dispose();
    // The existing API permits awaiting all serialized writes via flush even
    // after ChangeNotifier disposal; disposal's preceding snapshot is retained.
    await preferences.flush();
    expect((jsonDecode(await file.readAsString()) as Map)['scrollOffset'], 30);
  });
}
