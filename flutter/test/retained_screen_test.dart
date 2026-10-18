import 'package:cookdex/ui/retained_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hidden parent updates are applied on reveal', (tester) async {
    var builds = 0;
    var visible = true;
    var value = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return RetainedScreen(
              visible: visible,
              child: Builder(
                builder: (_) {
                  builds++;
                  return Text('$value');
                },
              ),
            );
          },
        ),
      ),
    );
    update(() => visible = false);
    await tester.pump();
    final before = builds;
    update(() => value = 20);
    await tester.pump();
    expect(builds, before);
    update(() => visible = true);
    await tester.pump();
    expect(find.text('20'), findsOneWidget);
  });
  testWidgets('hidden viewport stays stable and catches up on reveal', (
    tester,
  ) async {
    var builds = 0;
    var visible = true;
    var inset = 0.0;
    late StateSetter update;
    final child = Builder(
      builder: (context) {
        builds++;
        return Text('${MediaQuery.viewInsetsOf(context).bottom}');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
              child: RetainedScreen(visible: visible, child: child),
            );
          },
        ),
      ),
    );
    update(() => visible = false);
    await tester.pump();
    final before = builds;
    for (var i = 1; i <= 10; i++) {
      update(() => inset = i * 20);
      await tester.pump();
    }
    expect(builds, before);
    expect(find.text('0.0'), findsOneWidget);
    update(() => visible = true);
    await tester.pump();
    expect(find.text('200.0'), findsOneWidget);
    expect(builds, before + 1);
  });

  testWidgets('hidden status listener stops and reads latest state on reveal', (
    tester,
  ) async {
    final status = ValueNotifier(0);
    var builds = 0;
    var enabled = true;
    late StateSetter update;
    final child = VisibleListenableBuilder(
      listenable: status,
      builder: (_) {
        builds++;
        return Text('${status.value}');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return TickerMode(enabled: enabled, child: child);
          },
        ),
      ),
    );
    update(() => enabled = false);
    await tester.pump();
    final before = builds;
    status.value = 10;
    await tester.pump();
    expect(builds, before);
    update(() => enabled = true);
    await tester.pump();
    expect(find.text('10'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    status.dispose();
  });
}
