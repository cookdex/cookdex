import 'package:cookdex/ui/feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _host(
  WidgetTester tester, {
  GlobalKey<ScaffoldMessengerState>? messengerKey,
}) async {
  late BuildContext feedbackContext;
  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: messengerKey,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            feedbackContext = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  return feedbackContext;
}

Future<void> _showAnimation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  // Start the visibility timer after the entry animation completes.
  await tester.pump();
}

void main() {
  testWidgets('confirmation auto-dismisses after two seconds', (tester) async {
    final context = await _host(tester);
    showFeedback(context, 'Copied text');
    await _showAnimation(tester);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 2));
    expect(snackBar.persist, isFalse);
    expect(snackBar.action, isNull);
    await tester.pump(const Duration(milliseconds: 1900));
    expect(find.text('Copied text'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final kind in [FeedbackKind.destructive, FeedbackKind.error]) {
    testWidgets('$kind auto-dismisses after four seconds', (tester) async {
      final context = await _host(tester);
      showFeedback(context, 'Longer feedback', kind: kind);
      await _showAnimation(tester);
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.duration, const Duration(seconds: 4));
      expect(snackBar.persist, isFalse);
      await tester.pump(const Duration(milliseconds: 3900));
      expect(find.text('Longer feedback'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  testWidgets('Undo is available but does not keep feedback persistent', (
    tester,
  ) async {
    final context = await _host(tester);
    var undoCount = 0;
    showFeedback(context, 'Item removed', onUndo: () => undoCount++);
    await _showAnimation(tester);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 4));
    expect(snackBar.persist, isFalse);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(undoCount, 0);

    showFeedback(context, 'Item removed', onUndo: () => undoCount++);
    await _showAnimation(tester);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undoCount, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('newest feedback replaces visible and queued messages', (
    tester,
  ) async {
    final context = await _host(tester);
    final messenger = ScaffoldMessenger.of(context);
    showFeedback(context, 'Old feedback', onUndo: () {});
    await _showAnimation(tester);
    messenger.showSnackBar(const SnackBar(content: Text('Queued feedback')));
    showFeedback(context, 'Newest feedback');
    await _showAnimation(tester);
    expect(find.text('Old feedback'), findsNothing);
    expect(find.text('Queued feedback'), findsNothing);
    expect(find.text('Newest feedback'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('same-frame feedback burst keeps only the newest message', (
    tester,
  ) async {
    final context = await _host(tester);
    showFeedback(context, 'First');
    showFeedback(context, 'Second');
    showFeedback(context, 'Third');
    await _showAnimation(tester);
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsNothing);
    expect(find.text('Third'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('explicit messenger targets the local shopping scaffold', (
    tester,
  ) async {
    final outer = GlobalKey<ScaffoldMessengerState>();
    final local = GlobalKey<ScaffoldMessengerState>();
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: outer,
        home: Scaffold(
          body: ScaffoldMessenger(
            key: local,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );
    showFeedbackWithMessenger(
      local.currentState!,
      'Local error',
      kind: FeedbackKind.error,
    );
    await _showAnimation(tester);
    expect(find.text('Local error'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(local), matching: find.byType(SnackBar)),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
