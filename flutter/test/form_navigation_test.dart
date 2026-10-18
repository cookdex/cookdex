import 'dart:async';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/navigation_feedback.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart'
    as editor_helpers
    show controller, ClearFailureStorage, enterFieldText;
import 'import_test.dart' show ImportFakeService;

class _TrackingStorage extends MemoryDraftStorage {
  int clears = 0;
  @override
  Future<void> clear() async {
    clears++;
    await super.clear();
  }
}

class _DelayedStorage extends _TrackingStorage {
  final gate = Completer<void>();
  @override
  Future<void> write(Map<String, dynamic> value) async {
    await gate.future;
    await super.write(value);
  }
}

Future<void> _gesture(
  WidgetTester tester,
  String method, [
  double? progress,
]) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        progress == null
            ? null
            : <String, dynamic>{
                'touchOffset': <double>[5 + 250 * progress, 300],
                'progress': progress,
                'swipeEdge': 0,
              },
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

Future<MaterialPageRoute<void>> _showForm(
  WidgetTester tester,
  Widget form, {
  bool reduced = false,
}) async {
  late MaterialPageRoute<void> route;
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              route = cookdexRoute<void>(context, builder: (_) => form);
              Navigator.of(context).push(route);
            },
            child: const Text('Origin'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Origin'));
  await tester.pumpAndSettle();
  return route;
}

Future<void> _preview(WidgetTester tester, String title) async {
  await _gesture(tester, 'startBackGesture', 0);
  await _gesture(tester, 'updateBackGestureProgress', .4);
  expect(
    tester
        .getTopLeft(
          find.descendant(of: find.byType(AppBar), matching: find.text(title)),
        )
        .dx,
    greaterThan(0),
  );
  expect(find.text('Origin'), findsOneWidget);
}

void main() {
  testWidgets('import commit waits for queued draft storage before leaving', (
    tester,
  ) async {
    final storage = _DelayedStorage();
    final service = ImportFakeService();
    final controller = ImportController(service: service, storage: storage);
    addTearDown(controller.dispose);
    await _showForm(
      tester,
      ImportScreen(controller: controller, onReview: (_, _) async => null),
    );
    await tester.enterText(find.byType(TextField), 'Persist before leaving');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await _preview(tester, 'Smart Import');
    await _gesture(tester, 'commitBackGesture');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.byType(ImportScreen), findsOneWidget);
    expect(service.cancelled, 1);
    storage.gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Origin'), findsOneWidget);
    expect((await storage.read())!['text'], 'Persist before leaving');
  });

  testWidgets(
    'reduced-motion import Back retains input and leaves without preview',
    (tester) async {
      final storage = _TrackingStorage();
      final service = ImportFakeService();
      final controller = ImportController(service: service, storage: storage);
      addTearDown(controller.dispose);
      final route = await _showForm(
        tester,
        ImportScreen(controller: controller, onReview: (_, _) async => null),
        reduced: true,
      );
      await tester.enterText(find.byType(TextField), 'Reduced-motion draft');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final position = tester.getTopLeft(find.byType(ImportScreen));
      await _gesture(tester, 'startBackGesture', 0);
      await _gesture(tester, 'updateBackGestureProgress', .4);
      expect(tester.getTopLeft(find.byType(ImportScreen)), position);
      expect(route.transitionDuration, Duration.zero);
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect((await storage.read())!['text'], 'Reduced-motion draft');
    },
  );

  testWidgets(
    'pristine editor previews, cancel keeps it and commit leaves once',
    (tester) async {
      final storage = _TrackingStorage();
      final (controller, _, _) = await editor_helpers.controller(
        storage: storage,
      );
      final route = await _showForm(
        tester,
        RecipeEditor(controller: controller),
      );
      expect(route.popGestureEnabled, isTrue);
      await _preview(tester, 'Write a recipe');
      await _gesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Write a recipe'), findsOneWidget);
      expect(storage.clears, 0);
      await _preview(tester, 'Write a recipe');
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(storage.clears, 1);
    },
  );

  testWidgets(
    'dirty editor preview cancel and rejected discard preserve raw draft',
    (tester) async {
      final storage = _TrackingStorage();
      final (controller, _, _) = await editor_helpers.controller(
        storage: storage,
      );
      await _showForm(tester, RecipeEditor(controller: controller));
      await editor_helpers.enterFieldText(
        tester,
        find.byKey(const ValueKey('title')),
        'Unsaved soup',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await controller.flush();
      await _preview(tester, 'Write a recipe');
      await _gesture(tester, 'cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(controller.draft.title, 'Unsaved soup');
      expect(storage.clears, 0);
      await _preview(tester, 'Write a recipe');
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Write a recipe'), findsOneWidget);
      expect(controller.dirty, isTrue);
      expect((await storage.read())!['title'], 'Unsaved soup');
      await _preview(tester, 'Write a recipe');
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(storage.clears, 1);
      expect(await storage.read(), isNull);
    },
  );

  testWidgets(
    'predictive editor discard storage failure keeps form and draft',
    (tester) async {
      final (controller, _, _) = await editor_helpers.controller(
        storage: editor_helpers.ClearFailureStorage(),
      );
      await _showForm(tester, RecipeEditor(controller: controller));
      await editor_helpers.enterFieldText(
        tester,
        find.byKey(const ValueKey('title')),
        'Retained soup',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await _preview(tester, 'Write a recipe');
      await _gesture(tester, 'commitBackGesture');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Write a recipe'), findsOneWidget);
      expect(controller.dirty, isTrue);
      expect(find.text('Could not discard the local draft.'), findsOneWidget);
    },
  );

  testWidgets(
    'busy import previews, cancellation keeps request, commit cancels and flushes',
    (tester) async {
      final service = ImportFakeService()
        ..pending = Completer<ImportDiscovery>();
      final storage = _TrackingStorage();
      final controller = ImportController(service: service, storage: storage);
      addTearDown(controller.dispose);
      await _showForm(
        tester,
        ImportScreen(controller: controller, onReview: (_, _) async => null),
      );
      await tester.enterText(find.byType(TextField), 'Original import text');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await tester.pump();
      expect(controller.busy, isTrue);
      await _preview(tester, 'Smart Import');
      await _gesture(tester, 'cancelBackGesture');
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.busy, isTrue);
      expect(service.cancelled, 0);
      await _preview(tester, 'Smart Import');
      await _gesture(tester, 'commitBackGesture');
      expect(service.cancelled, 1);
      // A response delivered while the preview is settling must not push review.
      service.pending!.complete(service.result);
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Origin'), findsOneWidget);
      expect(service.cancelled, 1);
      expect((await storage.read())!['text'], 'Original import text');
      expect(storage.clears, 0);
      await tester.pump();
      expect(find.text('Choose one recipe'), findsNothing);
      expect(controller.text, 'Original import text');
    },
  );

  testWidgets('reduced-motion gesture still uses dirty editor confirmation', (
    tester,
  ) async {
    final (controller, _, _) = await editor_helpers.controller();
    await _showForm(
      tester,
      RecipeEditor(controller: controller),
      reduced: true,
    );
    await editor_helpers.enterFieldText(
      tester,
      find.byKey(const ValueKey('title')),
      'Unsaved soup',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _gesture(tester, 'startBackGesture', 0);
    await _gesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.dirty, isTrue);
    expect(find.text('Write a recipe'), findsOneWidget);
  });
}
