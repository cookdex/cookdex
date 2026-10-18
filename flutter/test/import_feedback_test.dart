import 'dart:convert';
import 'dart:io';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/src/rust/api.dart' as core;
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakeService, candidate;

class _LinkService extends ImportFakeService {
  final List<bool> aiChoices = [];

  @override
  Future<ImportDiscovery> link(String value, {bool useAi = false}) async {
    aiChoices.add(useAi);
    received = value;
    return ImportDiscovery(candidates: [candidate('link', 'Linked recipe')]);
  }
}

class _FallbackLinkService extends _LinkService {
  bool incomplete = false, downloadFailed = false;
  @override
  Future<ImportDiscovery> link(String value, {bool useAi = false}) async {
    final normal = await super.link(value, useAi: useAi);
    if (useAi) return normal;
    if (downloadFailed) throw const HttpException('Page could not be fetched.');
    return ImportDiscovery(
      candidates: incomplete ? normal.candidates : const [],
      warnings: const ['Embedded recipe data is missing or incomplete.'],
      canTryWithAi: true,
    );
  }
}

class _ToolsService extends ImportFakeService
    implements ImportServiceToolsProvider {
  core.ProviderMode? viewedMode;
  bool? viewedPhotos;
  bool cleared = false, failClear = false;
  @override
  Future<String> jsonPrompt({
    bool photos = false,
    core.ProviderMode mode = core.ProviderMode.recipe,
  }) async {
    viewedMode = mode;
    viewedPhotos = photos;
    return 'Return JSON with written quantities.';
  }

  @override
  Future<String?> lastAiDiagnostics() async => cleared
      ? null
      : 'Mode: UrlRecipe\nModel: test-model\nInstructions: JSON\nReply: {}\nValidation: missing title';
  @override
  Future<void> clearAiDiagnostics() async {
    if (failClear) throw StateError('Synthetic storage failure');
    cleared = true;
  }
}

ImportPhoto _photo(String id) => ImportPhoto(
  id: id,
  jpeg: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aDCkAAAAASUVORK5CYII=',
  ),
);

Future<void> _show(WidgetTester tester, ImportController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      home: ImportScreen(
        controller: controller,
        onReview: (_, _) async => null,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('Use AI choice survives clear and fresh preferences load', () async {
    final root = await Directory.systemTemp.createTemp('cookdex-import-prefs-');
    addTearDown(() => root.delete(recursive: true));
    final path = '${root.path}/ui-preferences.json';
    final preferences = await LocalPreferences.load(path);
    final controller = ImportController(
      service: _LinkService(),
      storage: MemoryDraftStorage(),
      preferences: preferences,
    )..tab = ImportTab.link;
    controller.setUseAiForLink(true);
    controller.link = 'https://example.test/recipe';
    controller.changed();
    await controller.clear();
    expect(controller.useAiForLink, isTrue);
    expect(controller.link, isEmpty);
    controller.dispose();
    preferences.dispose();
    final restoredPreferences = await LocalPreferences.load(path);
    final restored = ImportController(
      service: _LinkService(),
      storage: MemoryDraftStorage(),
      preferences: restoredPreferences,
    )..tab = ImportTab.link;
    expect(restored.useAiForLink, isTrue);
    await restored.discover();
    expect((restored.service as _LinkService).aiChoices, [true]);
    restored.dispose();
    restoredPreferences.dispose();
    await restoredPreferences.flush();
  });

  testWidgets('successful import keeps the AI checkbox preference', (
    tester,
  ) async {
    final preferences = LocalPreferences.memory()..setUseAiForLink(true);
    final controller = ImportController(
      service: _LinkService(),
      storage: MemoryDraftStorage(),
      preferences: preferences,
    )..tab = ImportTab.link;
    controller.link = 'https://example.test/recipe';
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: ImportScreen(
          controller: controller,
          onReview: (_, candidate) async => candidate.recipe,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
    await tester.pumpAndSettle();
    expect(controller.link, isEmpty);
    expect(preferences.useAiForLink, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    preferences.dispose();
  });

  for (final failure in ['missing', 'incomplete', 'download']) {
    testWidgets('$failure embedded link offers one-tap AI retry', (
      tester,
    ) async {
      final service = _FallbackLinkService()
        ..incomplete = failure == 'incomplete'
        ..downloadFailed = failure == 'download';
      final controller = ImportController(
        service: service,
        storage: MemoryDraftStorage(),
      )..tab = ImportTab.link;
      await _show(tester, controller);
      await tester.enterText(
        find.byType(TextField),
        'https://example.test/recipe',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false]);
      final retry = failure == 'incomplete'
          ? find.widgetWithText(FilledButton, 'Try with AI')
          : find.widgetWithText(OutlinedButton, 'Try with AI');
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false, true]);
      expect(service.received, 'https://example.test/recipe');
      expect(controller.useAiForLink, isFalse);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets(
    'Smart Import settings shows both prompts and last import validation',
    (tester) async {
      final service = _ToolsService();
      final controller = ImportController(
        service: service,
        storage: MemoryDraftStorage(),
      )..tab = ImportTab.link;
      await _show(tester, controller);
      await tester.tap(find.text('Smart Import settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View prompt'));
      await tester.pumpAndSettle();
      expect(find.text('In-app JSON prompt (link)'), findsOneWidget);
      expect(find.text('Copy Text v1 prompt'), findsOneWidget);
      expect(find.text('Return JSON with written quantities.'), findsOneWidget);
      expect(find.text('Keep quantities exactly as written.'), findsOneWidget);
      expect(service.viewedMode, core.ProviderMode.urlRecipe);
      expect(service.viewedPhotos, isFalse);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last Smart Import'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Validation: missing title'), findsOneWidget);
      service.failClear = true;
      await tester.tap(find.text('Clear record'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not clear the last Smart Import.'),
        findsOneWidget,
      );
      expect(service.cleared, isFalse);
      expect(tester.takeException(), isNull);
      service.failClear = false;
      await tester.tap(find.text('Clear record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last Smart Import'));
      await tester.pumpAndSettle();
      expect(find.text('No Smart Import has been recorded.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'link checkbox changes the next Import without importing itself',
    (tester) async {
      final service = _LinkService();
      final controller = ImportController(
        service: service,
        storage: MemoryDraftStorage(),
      )..tab = ImportTab.link;
      await _show(tester, controller);
      await tester.enterText(
        find.byType(TextField),
        'https://example.test/recipe',
      );
      final checkbox = find.byType(CheckboxListTile);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false]);

      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
      expect(service.aiChoices, [false]);
      await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false, true]);
      expect(service.received, 'https://example.test/recipe');

      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false, true, false]);
      expect(find.text('Smart Import settings'), findsOneWidget);
      expect(find.text('Smart Import'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'large photo previews can reorder and delete with badge controls',
    (tester) async {
      final storage = MemoryDraftStorage();
      final controller = ImportController(
        service: ImportFakeService(),
        storage: storage,
      )..tab = ImportTab.photos;
      controller.photos.addAll([
        _photo('first'),
        _photo('second'),
        _photo('third'),
      ]);
      await _show(tester, controller);
      expect(tester.getSize(find.byType(Image).first), const Size(160, 160));
      expect(find.text('3 of 8'), findsOneWidget);
      final preview = tester.getRect(find.byType(Image).first);
      final badge = tester.getRect(find.byTooltip('Remove photo 1'));
      expect(preview.contains(badge.center), isTrue);
      expect(badge.width, greaterThanOrEqualTo(48));
      expect(badge.height, greaterThanOrEqualTo(48));
      final camera = tester.getRect(find.text('Camera'));
      final gallery = tester.getRect(find.text('Gallery'));
      expect(camera.top, greaterThan(preview.bottom));
      expect(gallery.left - camera.right, greaterThanOrEqualTo(24));
      expect(
        tester.getRect(find.text('3 of 8')).top,
        greaterThan(camera.bottom),
      );

      final handle = find.byType(ReorderableDragStartListener).first;
      final drag = await tester.startGesture(tester.getCenter(handle));
      await tester.pump();
      await drag.moveBy(const Offset(24, 0));
      await tester.pump();
      await drag.moveBy(const Offset(96, 0));
      await tester.pump(const Duration(milliseconds: 600));
      await drag.up();
      await tester.pumpAndSettle();
      expect(controller.photos.map((photo) => photo.id), [
        'second',
        'first',
        'third',
      ]);

      await tester.tap(find.byTooltip('Remove photo 1'));
      await tester.pumpAndSettle();
      expect(controller.photos.map((photo) => photo.id), ['first', 'third']);
      expect(find.text('2 of 8'), findsOneWidget);
      await controller.flush();
      expect((await storage.read())!['photos'].length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('populated photos fit narrow screen and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ImportController(
      service: ImportFakeService(),
      storage: MemoryDraftStorage(),
    )..tab = ImportTab.photos;
    controller.photos.addAll(List.generate(8, (index) => _photo('$index')));
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ImportScreen(
          controller: controller,
          onReview: (_, _) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('8 of 8'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Camera'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Gallery'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Remove photo 1'));
    await tester.pumpAndSettle();
    expect(find.text('7 of 8'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
