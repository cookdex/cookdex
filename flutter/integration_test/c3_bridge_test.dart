import 'package:cookdex/c3_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('C3 typed services survive the native bridge', (tester) async {
    await verifyC3();
  });
}
