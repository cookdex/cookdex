import 'dart:convert';
import 'dart:io';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/incoming_share.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/src/rust/api.dart' as core;
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/smart_settings_screen.dart';
import 'package:cookdex/ui/smart_action_button.dart';
import 'package:cookdex/youtube_import.dart'
    show youtubeKeyNeeded, youtubeNotPublic;
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakeService, candidate;

class _LinkService extends ImportFakeService {
  final List<bool> aiChoices = [];

  @override
  Future<ImportDiscovery> link(
    String value, {
    bool useAi = false,
    ImportPhaseCallback? onPhase,
  }) async {
    aiChoices.add(useAi);
    received = value;
    return ImportDiscovery(candidates: [candidate('link', 'Linked recipe')]);
  }
}

class _FallbackLinkService extends _LinkService {
  bool incomplete = false, downloadFailed = false;
  @override
  Future<ImportDiscovery> link(
    String value, {
    bool useAi = false,
    ImportPhaseCallback? onPhase,
  }) async {
    final normal = await super.link(value, useAi: useAi);
    if (useAi) return normal;
    if (downloadFailed) throw const HttpException('Page could not be fetched.');
    return ImportDiscovery(
      candidates: incomplete ? normal.candidates : const [],
      warnings: const ['Embedded recipe data is missing or incomplete.'],
      websiteAiHint: true,
    );
  }
}

class _WatchService extends ImportFakeService implements YoutubeWatchImport {
  final confirmations = <String>[];
  @override
  Future<ImportDiscovery> watchAnyway(
    String url, {
    ImportPhaseCallback? onPhase,
  }) async {
    confirmations.add(url);
    return result;
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

Future<void> _show(
  WidgetTester tester,
  ImportController controller, {
  IncomingShare? share,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      home: ImportScreen(
        controller: controller,
        onReview: (_, _) async => null,
        initialInput: share?.apply,
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

  testWidgets('successful import keeps the AI switch preference', (
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
    await tester.tap(find.byKey(const Key('smart-import-action')));
    await tester.pumpAndSettle();
    expect(controller.link, isEmpty);
    expect(preferences.useAiForLink, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    preferences.dispose();
  });

  testWidgets('Paste is explicit and Clear affects only the visible input', (
    tester,
  ) async {
    final controller = ImportController(
      service: ImportFakeService(),
      storage: MemoryDraftStorage(),
    )..text = 'ingredient';
    controller.photos.add(_photo('keep'));
    var reads = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        reads++;
        return {'text': 'https://example.test/soup'};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    await _show(tester, controller);
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    expect(reads, 0);
    expect(find.text('Clear').hitTestable(), findsNothing);
    final field = find.byType(TextField);
    final slot = find.descendant(
      of: field,
      matching: find.byType(FilledButton),
    );
    final aiSwitch = find.byType(SwitchListTile);
    List<Rect> bounds() => [field, slot, aiSwitch].map(tester.getRect).toList();
    final emptyBounds = bounds();
    expect(emptyBounds[2].top - emptyBounds[0].bottom, inInclusiveRange(0, 12));
    await tester.enterText(field, 'typed');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 55));
    expect(bounds(), emptyBounds);
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsNothing);
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsNothing);
    expect(reads, 0);
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(bounds(), emptyBounds);
    expect(reads, 1);
    expect(controller.link, 'https://example.test/soup');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear link?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.link, 'https://example.test/soup');
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear').last);
    await tester.pumpAndSettle();
    expect(find.text('Clear').hitTestable(), findsNothing);
    expect(controller.link, isEmpty);
    expect(controller.text, 'ingredient');
    expect(controller.photos.single.id, 'keep');
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'keyboard covers the fixed action while the text caret stays visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 740);
      tester.view.viewPadding = const FakeViewPadding(bottom: 24);
      tester.view.padding = const FakeViewPadding(bottom: 24);
      addTearDown(tester.view.reset);
      final controller = ImportController(
        service: ImportFakeService(),
        storage: MemoryDraftStorage(),
      );
      await _show(tester, controller);
      final field = find.byType(TextField);
      final action = find.byKey(const Key('smart-import-action'));
      final closed = tester.getRect(action);
      await tester.tap(field);
      tester.view.padding = FakeViewPadding.zero;
      tester.view.viewInsets = const FakeViewPadding(bottom: 324);
      await tester.pumpAndSettle();
      final text = List.generate(
        32,
        (index) => 'Recipe line ${index + 1}',
      ).join('\n');
      await tester.enterText(field, text);
      await tester.pumpAndSettle();
      final editable = tester
          .state<EditableTextState>(find.byType(EditableText))
          .renderEditable;
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: text.length),
      );
      expect(editable.localToGlobal(caret.topLeft).dy, greaterThan(0));
      expect(
        editable.localToGlobal(caret.bottomLeft).dy,
        lessThanOrEqualTo(416),
      );
      expect(tester.getRect(action), closed);
      expect(closed.top, greaterThan(416));
      tester.view.resetViewInsets();
      tester.view.padding = const FakeViewPadding(bottom: 24);
      await tester.pumpAndSettle();
      expect(tester.getRect(action), closed);
      expect(controller.text, text);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  for (final failure in ['missing', 'incomplete', 'download']) {
    testWidgets('$failure embedded link points to the existing AI switch', (
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
      await tester.tap(find.byKey(const Key('smart-import-action')));
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false]);
      expect(find.text('Try with AI'), findsNothing);
      expect(
        find.textContaining('turn on Use AI for this link'),
        findsOneWidget,
      );
      if (failure == 'incomplete') {
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
      }
      final toggle = find.byType(SwitchListTile);
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false]);
      await tester.tap(find.byKey(const Key('smart-import-action')));
      await tester.pumpAndSettle();
      expect(service.aiChoices, [false, true]);
      expect(service.received, 'https://example.test/recipe');
      expect(controller.useAiForLink, isTrue);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('automatic social routes preserve the ordinary AI choice', (
    tester,
  ) async {
    final controller = ImportController(
      service: ImportFakeService(),
      storage: MemoryDraftStorage(),
    )..tab = ImportTab.link;
    controller.setUseAiForLink(true);
    await _show(tester, controller);
    for (final (host, automatic) in [
      ('www.youtube.com', true),
      ('youtu.be', true),
      ('www.tiktok.com', true),
      ('www.instagram.com', true),
      ('pin.it', true),
      ('www.pinterest.com', true),
      ('www.reddit.com', true),
      ('www.facebook.com', true),
      ('x.com', true),
      ('www.threads.com', true),
      ('youtube.com.example', false),
      ('kitchen.example', false),
    ]) {
      await tester.enterText(find.byType(TextField), 'https://$host/recipe');
      await tester.pumpAndSettle();
      expect(
        find.text('Use AI for this link'),
        automatic ? findsNothing : findsOneWidget,
      );
      expect(controller.useAiForLink, isTrue);
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  for (final shared in [false, true]) {
    testWidgets(
      '${shared ? 'Shared' : 'Pasted'} social links show guidance before import',
      (tester) async {
        String clipboard = '';
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async =>
              call.method == 'Clipboard.getData' ? {'text': clipboard} : null,
        );
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        for (final (name, url) in [
          ('TikTok', 'https://vm.tiktok.com/Test123/'),
          ('Instagram', 'https://instagr.am/reel/Test123/'),
          ('Threads', 'https://www.threads.net/@sample/post/Test123'),
          ('Facebook', 'https://fb.watch/Test123/'),
          ('X', 'https://t.co/Test123'),
          ('Reddit', 'https://redd.it/Test123'),
          ('Pinterest', 'https://pin.it/Test123'),
          ('YouTube', 'https://youtu.be/CookdexDemo'),
        ]) {
          final service = _LinkService();
          final c = ImportController(
            service: service,
            storage: MemoryDraftStorage(),
          )..tab = ImportTab.link;
          clipboard = url;
          await _show(
            tester,
            c,
            share: shared ? IncomingShare({'text': url}) : null,
          );
          if (!shared) {
            await tester.tap(find.text('Paste'));
            await tester.pumpAndSettle();
          }
          expect(c.link, url);
          expect(find.byType(SwitchListTile), findsNothing);
          final action = find.byKey(const Key('smart-import-action'));
          expect(tester.widget<SmartActionButton>(action).onPressed, isNull);
          expect(service.aiChoices, isEmpty);
          if (name == 'YouTube') {
            expect(find.text(youtubeKeyNeeded), findsOneWidget);
            await tester.tap(find.text('Add Gemini API key'));
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<SmartSettingsScreen>(find.byType(SmartSettingsScreen))
                  .keyPage,
              isTrue,
            );
            service.platform.hasKey = true;
            await tester.tap(find.byTooltip('Back'));
            await tester.pumpAndSettle();
            expect(find.text(youtubeKeyNeeded), findsNothing);
            expect(c.link, url);
            expect(service.aiChoices, isEmpty);
            await tester.tap(action);
            await tester.pumpAndSettle();
            expect(service.aiChoices, [true]);
            expect(c.useAiForLink, isFalse);
          } else {
            expect(
              find.textContaining("cookdex can't import from $name."),
              findsOneWidget,
            );
            if (name == 'Pinterest') {
              expect(find.textContaining('tap Visit'), findsOneWidget);
            } else {
              expect(find.text('Use photos'), findsOneWidget);
              expect(find.text('Paste text'), findsOneWidget);
            }
          }
          await tester.pumpWidget(const SizedBox());
          c.dispose();
        }
      },
    );
  }

  testWidgets(
    'unknown duration after a redirect needs a tap and retries use the same video',
    (tester) async {
      const url = 'https://www.youtube.com/watch?v=CookdexDemo';
      const shared = 'https://kitchen.example/shared';
      final service = _WatchService()
        ..platform.hasKey = true
        ..result = const ImportDiscovery(
          candidates: [],
          warnings: ['Unknown duration'],
          fallback: true,
          canWatchAnyway: true,
          source: url,
        );
      final c = ImportController(
        service: service,
        storage: MemoryDraftStorage(),
      );
      await _show(tester, c, share: const IncomingShare({'text': shared}));
      await tester.tap(find.byKey(const Key('smart-import-action')));
      await tester.pumpAndSettle();
      expect(service.confirmations, isEmpty);
      expect(c.linkUnavailable, isTrue);
      expect(c.link, shared);
      expect(find.byType(SwitchListTile), findsNothing);
      service.result = const ImportDiscovery(
        candidates: [],
        warnings: ['Temporary failure'],
        fallback: true,
        canRetryWatch: true,
      );
      await tester.tap(find.text('Watch anyway'));
      await tester.pumpAndSettle();
      expect(service.confirmations, [url]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(service.confirmations, [url, url]);
      await tester.enterText(
        find.byType(TextField),
        'https://example.test/other',
      );
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Watch anyway'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('a redirected private video retains the YouTube refusal', (
    tester,
  ) async {
    const video = 'https://www.youtube.com/watch?v=CookdexDemo';
    final service = _WatchService()
      ..result = const ImportDiscovery(
        candidates: [],
        source: video,
        warnings: [youtubeNotPublic],
        fallback: true,
      );
    service.platform.hasKey = true;
    final controller = ImportController(
      service: service,
      storage: MemoryDraftStorage(),
    );
    await _show(
      tester,
      controller,
      share: const IncomingShare({'text': 'https://kitchen.example/link'}),
    );
    await tester.tap(find.byKey(const Key('smart-import-action')));
    await tester.pumpAndSettle();
    expect(find.textContaining(youtubeNotPublic), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(controller.linkUnavailable, isTrue);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('link fallback preserves input and offers both manual routes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 740);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const message = 'This site didn’t share its recipe.';
    final service = ImportFakeService()
      ..result = const ImportDiscovery(
        candidates: [],
        warnings: [message],
        fallback: true,
      );
    const link = 'https://example.test/recipe';
    final storage = MemoryDraftStorage();
    final controller = ImportController(service: service, storage: storage)
      ..tab = ImportTab.link
      ..link = link
      ..text = 'Existing recipe text';
    await _show(tester, controller);
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    for (final (action, tab) in [
      ('Use photos', ImportTab.photos),
      ('Paste text', ImportTab.text),
    ]) {
      await tap(find.byKey(const Key('smart-import-action')));
      expect(find.textContaining(message), findsOneWidget);
      await controller.flush();
      expect((await storage.read())!['manualInput'], isTrue);
      final button = find.text(action);
      await tap(button);
      expect(controller.tab, tab);
      expect(controller.link, link);
      expect(controller.text, 'Existing recipe text');
      expect(find.textContaining(message), findsNothing);
      expect(
        find.text(tab == ImportTab.photos ? 'Gallery' : 'Paste'),
        findsOneWidget,
      );
      await tap(find.text('Link'));
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets(
    'Smart Import settings shows both prompts and last import validation',
    (tester) async {
      final service = _ToolsService();
      final controller =
          ImportController(service: service, storage: MemoryDraftStorage())
            ..tab = ImportTab.link
            ..text = 'Family soup'
            ..link = 'https://example.test/soup'
            ..photos.add(_photo('front'));
      await _show(tester, controller);
      await tester.tap(find.text('Smart Import settings'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SmartSettingsScreen>(find.byType(SmartSettingsScreen))
            .service,
        same(service),
      );
      await tester.ensureVisible(find.text('View prompts'));
      await tester.tap(find.text('View prompts'));
      await tester.pumpAndSettle();
      expect(find.text('In-app JSON prompt (Link)'), findsOneWidget);
      expect(find.text('Copy Text v1 prompt'), findsOneWidget);
      expect(
        find.text('Return JSON with written quantities.'),
        findsNWidgets(3),
      );
      expect(find.text('Keep quantities exactly as written.'), findsOneWidget);
      expect(service.viewedMode, core.ProviderMode.recipe);
      expect(service.viewedPhotos, isTrue);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Last Smart Import'));
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
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      service.failClear = false;
      await tester.tap(find.text('Clear record'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Last Smart Import'));
      await tester.tap(find.text('Last Smart Import'));
      await tester.pumpAndSettle();
      expect(find.text('No Smart Import has been recorded.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(controller.tab, ImportTab.link);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        controller.link,
      );
      expect(controller.text, 'Family soup');
      expect(controller.photos.single.id, 'front');
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets('link switch changes the next Import without importing itself', (
    tester,
  ) async {
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
    final aiSwitch = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(aiSwitch).value, isFalse);
    await tester.tap(find.byKey(const Key('smart-import-action')));
    await tester.pumpAndSettle();
    expect(service.aiChoices, [false]);

    await tester.tap(aiSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(aiSwitch).value, isTrue);
    expect(service.aiChoices, [false]);
    await tester.tap(find.byKey(const Key('smart-import-action')));
    await tester.pumpAndSettle();
    expect(service.aiChoices, [false, true]);
    expect(service.received, 'https://example.test/recipe');

    await tester.tap(aiSwitch);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('smart-import-action')));
    await tester.pumpAndSettle();
    expect(service.aiChoices, [false, true, false]);
    expect(find.text('Smart Import settings'), findsOneWidget);
    expect(find.text('Smart Import'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

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
      expect(tester.getSize(find.byType(Image).first), const Size(104, 112));
      expect(find.text('3 of 8 photos'), findsOneWidget);
      final preview = tester.getRect(find.byType(Image).first);
      final badge = tester.getRect(find.byTooltip('Remove photo 1'));
      expect(preview.contains(badge.center), isTrue);
      expect(badge.width, greaterThanOrEqualTo(48));
      expect(badge.height, greaterThanOrEqualTo(48));
      final camera = tester.getRect(find.text('Camera'));
      final gallery = tester.getRect(find.text('Gallery'));
      expect(camera.bottom, lessThan(preview.top));
      expect(gallery.left - camera.right, greaterThanOrEqualTo(24));
      expect(
        tester.getRect(find.text('3 of 8 photos')).top,
        greaterThan(camera.bottom),
      );

      final handle = find.byType(ReorderableDelayedDragStartListener).first;
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      expect(handle.hitTestable(), findsOneWidget);
      final origin = tester.getCenter(handle);
      final neighbor = tester.getCenter(
        find.byType(ReorderableDelayedDragStartListener).at(1),
      );
      final drag = await tester.startGesture(origin);
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();
      // Move through the midpoint so the following tile slides left to
      // expose its drop slot. A single oversized move can skip that slot.
      for (var i = 1; i <= 12; i++) {
        await drag.moveTo(Offset.lerp(origin, neighbor, i / 15)!);
        await tester.pump(const Duration(milliseconds: 30));
      }
      await tester.pump(const Duration(milliseconds: 300));
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
      expect(find.text('2 of 8 photos'), findsOneWidget);
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
    expect(find.text('8 of 8 photos'), findsOneWidget);
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
    await tester.ensureVisible(find.byTooltip('Remove photo 1'));
    await tester.tap(find.byTooltip('Remove photo 1'));
    await tester.pumpAndSettle();
    expect(find.text('7 of 8 photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
