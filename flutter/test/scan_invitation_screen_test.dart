import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/pairing_screen.dart';
import 'package:cookdex/ui/scan_invitation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import 'fake_scanner_camera.dart';
import 'sync_controller_test.dart' show FakeSyncBackend;

void main() {
  late FakeScannerCamera camera;
  late CameraPlatform original;
  setUp(() {
    original = CameraPlatform.instance;
    camera = FakeScannerCamera();
    CameraPlatform.instance = camera;
  });
  tearDown(() {
    CameraPlatform.instance = original;
  });

  Future<void> open(WidgetTester tester, void Function(String?) result) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result(
                  await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ScanInvitationScreen(),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'only a valid bounded invitation returns once and releases camera',
    (tester) async {
      final results = <String?>[];
      await open(tester, results.add);
      expect(find.byKey(const Key('synthetic-camera-preview')), findsOneWidget);
      final reader = tester.widget<ReaderWidget>(find.byType(ReaderWidget));
      for (final code in [
        Code(text: 'recipe-pair:invalid', isValid: false),
        Code(isValid: true),
        Code(text: 'https://example.invalid', isValid: true),
        Code(text: 'recipe-pair:${'x' * 4085}', isValid: true),
      ]) {
        reader.onScan!(code);
        await tester.pump();
        expect(results, isEmpty);
        expect(find.byType(ScanInvitationScreen), findsOneWidget);
      }
      final boundary = 'recipe-pair:${'x' * 4084}';
      expect(boundary.length, 4096);
      reader.onScan!(Code(text: boundary, isValid: true));
      reader.onScan!(Code(text: 'recipe-pair:duplicate', isValid: true));
      await tester.pumpAndSettle();
      expect(results, [boundary]);
      await tester.pump(const Duration(seconds: 3));
      expect(camera.disposals, 1);
      reader.onScan!(Code(text: 'recipe-pair:late', isValid: true));
      expect(results, [boundary]);
    },
  );

  testWidgets('Back cancels without returning an invitation', (tester) async {
    final results = <String?>[];
    await open(tester, results.add);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(results, [null]);
    await tester.pump(const Duration(seconds: 3));
    expect(camera.disposals, 1);
  });

  testWidgets('camera-less devices offer an exit instead of endless loading', (
    tester,
  ) async {
    camera.noCameras = true;
    final results = <String?>[];
    await open(tester, results.add);
    expect(
      find.textContaining('Camera access is unavailable.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Back to pairing'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(results, [null]);
  });

  testWidgets('pause stops frames and resume restarts scanning', (
    tester,
  ) async {
    await open(tester, (_) {});
    await tester.pump(const Duration(milliseconds: 400));
    expect(camera.streamStarts, 1);
    expect(camera.streamStops, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(camera.streamStops, 1);
    await tester.pump();
    // Camera cancellation crosses asynchronous zones; fake-clock pumping alone
    // does not drain that work before the resume callback.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(camera.streamStarts, 2);
    expect(camera.disposals, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });

  testWidgets('native camera failure after startup offers the paste fallback', (
    tester,
  ) async {
    final results = <String?>[];
    await open(tester, results.add);
    camera.failCamera();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Camera access is unavailable.'),
      findsOneWidget,
    );
    expect(find.byType(ReaderWidget), findsNothing);
    expect(results, isEmpty);
    await tester.tap(find.text('Back to pairing'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(results, [null]);
  });

  testWidgets('controller setup error disables late scan callbacks', (
    tester,
  ) async {
    final results = <String?>[];
    await open(tester, results.add);
    final reader = tester.widget<ReaderWidget>(find.byType(ReaderWidget));
    reader.onControllerCreated!(null, Exception('Synthetic setup failure'));
    reader.onScan!(Code(text: 'recipe-pair:late', isValid: true));
    await tester.pumpAndSettle();
    expect(results, isEmpty);
    expect(
      find.textContaining('Camera access is unavailable.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to pairing'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(results, [null]);
  });

  testWidgets('denied camera returns to pairing and paste remains usable', (
    tester,
  ) async {
    camera.unavailable = true;
    final backend = FakeSyncBackend();
    final controller = SyncController(
      backend: backend,
      refreshRecipes: () async {},
      isAndroid: true,
      requestPermission: () async => true,
    );

    await controller.lifecycle(true);
    await tester.pumpWidget(
      MaterialApp(home: PairingScreen(controller: controller)),
    );
    await tester.tap(find.text('Join a device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Camera access is unavailable.'),
      findsOneWidget,
    );
    expect(backend.pairCodes, isEmpty);
    await tester.tap(find.text('Back to pairing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Paste invitation'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'recipe-pair:synthetic-pasted',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
    await tester.pumpAndSettle();
    expect(backend.pairCodes, ['recipe-pair:synthetic-pasted']);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
