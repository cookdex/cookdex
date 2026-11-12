import 'package:flutter_test/flutter_test.dart';

/// Exercise the same action whether the available width puts it in overflow.
Future<void> tapSelectionAction(
  WidgetTester tester,
  String tooltip,
  String label,
) async {
  final direct = find.byTooltip(tooltip);
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct);
  } else {
    await tester.tap(find.byTooltip('More selection actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).hitTestable());
  }
}
