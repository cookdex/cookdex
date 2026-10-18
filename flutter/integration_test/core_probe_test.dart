import 'package:cookdex/core_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native core creates, saves, rejects stale writes and reopens', (
    tester,
  ) async {
    expect(await verifyCore(), 0);
  });
}
