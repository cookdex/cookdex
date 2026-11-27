import 'package:cookdex/ui/phone_orientation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<List<String>> recordOrientations(WidgetTester tester) {
    final calls = <List<String>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          calls.add(List<String>.from(call.arguments as List));
        }
        return null;
      },
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.reset();
      tester.view.display.reset();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    return calls;
  }

  Future<void> mount(WidgetTester tester, {bool android = true}) =>
      tester.pumpWidget(
        PhoneOrientation(isAndroid: android, child: const SizedBox.shrink()),
      );

  for (final (name, size, portrait) in [
    ('portrait phone', const Size(390, 844), true),
    ('landscape phone', const Size(844, 390), true),
    ('just below tablet', const Size(599, 900), true),
    ('tablet threshold', const Size(600, 900), false),
    ('portrait tablet', const Size(800, 1280), false),
    ('landscape tablet', const Size(1280, 800), false),
  ]) {
    testWidgets('$name sets orientation from display logical size at startup', (
      tester,
    ) async {
      final calls = recordOrientations(tester);
      tester.view.display.devicePixelRatio = 3;
      tester.view.display.size = size * 3;
      // A split/letterboxed window must not decide the device class.
      tester.view.physicalSize = const Size(300, 500) * 3;
      await mount(tester);
      expect(calls, [
        portrait ? ['DeviceOrientation.portraitUp'] : <String>[],
      ]);
    });
  }

  testWidgets('folding and unfolding update without a window-size change', (
    tester,
  ) async {
    final calls = recordOrientations(tester);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.display.size = const Size(390, 844) * 2;
    await mount(tester);
    expect(calls, [
      ['DeviceOrientation.portraitUp'],
    ]);

    // The old phone window can remain letterboxed during the unfolding event.
    tester.view.display.size = const Size(800, 1000) * 2;
    await tester.pump();
    expect(calls.last, isEmpty);
    expect(tester.view.physicalSize, const Size(390, 844) * 2);

    tester.view.display.size = const Size(1000, 800) * 2;
    tester.view.physicalSize = const Size(500, 350) * 2;
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, [
      ['DeviceOrientation.portraitUp'],
      <String>[],
    ]);

    tester.view.display.size = const Size(390, 844) * 2;
    await tester.pump();
    expect(calls, [
      ['DeviceOrientation.portraitUp'],
      <String>[],
      ['DeviceOrientation.portraitUp'],
    ]);

    // Rotating the same phone does not release its portrait preference.
    tester.view.display.size = const Size(844, 390) * 2;
    await tester.pump();
    expect(calls, hasLength(3));

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.display.size = const Size(800, 1000) * 2;
    await tester.pump();
    expect(calls, hasLength(3));
  });

  testWidgets('unavailable display waits for usable metrics', (tester) async {
    final calls = recordOrientations(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.display.size = Size.zero;
    await mount(tester);
    expect(calls, isEmpty);
    tester.view.display.size = const Size(390, 844);
    await tester.pump();
    expect(calls, [
      ['DeviceOrientation.portraitUp'],
    ]);
  });

  testWidgets('Windows never sends orientation requests for any window size', (
    tester,
  ) async {
    final calls = recordOrientations(tester);
    tester.view.devicePixelRatio = 1;
    tester.view.display.size = const Size(390, 844);
    await mount(tester, android: false);
    for (final size in [
      const Size(844, 390),
      const Size(1280, 800),
      const Size(320, 200),
    ]) {
      tester.view.display.size = size;
      tester.view.physicalSize = size;
      await tester.pump();
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, isEmpty);
  });
}
