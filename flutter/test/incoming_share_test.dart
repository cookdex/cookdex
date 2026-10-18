import 'dart:async';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/incoming_share.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart'
    show ImportFakeService, ImportRepositoryFake, ShellPlatform;

class AndroidSharePlatform extends ShellPlatform {
  @override
  bool get isAndroid => true;
}

class ShareChannelFake {
  final queue = <Map<String, dynamic>>[];
  int finishes = 0;
  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(IncomingShares.channel, (call) async {
          if (call.method == 'take') {
            return queue.isEmpty ? null : queue.removeAt(0);
          }
          if (call.method == 'finishIfEmpty') {
            if (queue.isNotEmpty) return false;
            finishes++;
            return true;
          }
          return null;
        });
  }

  Future<void> ready() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          IncomingShares.channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('ready'),
          ),
          (_) {},
        );
  }

  void dispose() => TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(IncomingShares.channel, null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ready during an in-flight empty take is not lost', (
    tester,
  ) async {
    final first = Completer<Map<String, dynamic>?>();
    var takes = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(IncomingShares.channel, (call) async {
      if (call.method != 'take') return false;
      takes++;
      if (takes == 1) return first.future;
      if (takes == 2) return {'text': 'queued during reply'};
      return null;
    });
    final shares = IncomingShares(onReady: () {});
    shares.start();
    await tester.pump();
    await messenger.handlePlatformMessage(
      IncomingShares.channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('ready')),
      (_) {},
    );
    first.complete(null);
    await tester.pump();
    expect(shares.take()!.value['text'], 'queued during reply');
    await tester.pump();
    shares.dispose();
    messenger.setMockMethodCallHandler(IncomingShares.channel, null);
  });

  test(
    'incoming text and links preserve text and choose their matching tab',
    () async {
      final c = ImportController(
        service: ImportFakeService(),
        storage: MemoryDraftStorage(),
      );
      addTearDown(c.dispose);
      await const IncomingShare({'text': '  Recipe text\nKeep lines  '})
          .apply(c);
      expect(c.tab, ImportTab.text);
      expect(c.text, '  Recipe text\nKeep lines  ');
      await const IncomingShare({'text': ' https://example.com/soup '})
          .apply(c);
      expect(c.tab, ImportTab.link);
      expect(c.link, 'https://example.com/soup');
      await const IncomingShare({
        'text': 'https://example.com/soup plus commentary',
      }).apply(c);
      expect(c.tab, ImportTab.text);
      await c.flush();
    },
  );

  test('incoming photos retain order and partial errors; rejected share shows error', () async {
    final c = ImportController(
      service: ImportFakeService(),
      storage: MemoryDraftStorage(),
    );
    addTearDown(c.dispose);
    final one = Uint8List.fromList([1, 2]), two = Uint8List.fromList([3, 4]);
    await IncomingShare({
      'photos': [one, two],
      'originalIds': ['shared-original-1', 'shared-original-2'],
      'errors': ['One photo was unreadable.'],
    }).apply(c);
    expect(c.tab, ImportTab.photos);
    expect(c.photos.map((p) => p.jpeg), [one, two]);
    expect(c.photos.map((p) => p.originalId), [
      'shared-original-1',
      'shared-original-2',
    ]);
    expect(c.photos.map((p) => p.id).toSet(), hasLength(2));
    expect(c.warnings, contains('One photo was unreadable.'));
    await const IncomingShare({'error': 'The shared file is too large.'})
        .apply(c);
    expect(c.error, 'The shared file is too large.');
    expect(c.photos, hasLength(2));
    await c.flush();
  });

  testWidgets(
    'queue retains second share and only finishes when both queues empty',
    (tester) async {
      final native = ShareChannelFake()..install();
      addTearDown(native.dispose);
      native.queue.addAll([
        {'text': 'first', 'coldStart': true},
        {'text': 'second'},
      ]);
      final shares = IncomingShares(onReady: () {});
      addTearDown(shares.dispose);
      shares.start();
      await tester.pump();
      expect(shares.take()!.value['text'], 'first');
      expect(await shares.finishIfEmpty(), false);
      expect(native.finishes, 0);
      await tester.pump();
      expect(shares.take()!.value['text'], 'second');
      await tester.pump();
      expect(await shares.finishIfEmpty(), true);
      expect(native.finishes, 1);
    },
  );

  testWidgets(
    'incoming share waits for unsaved editor and preserves its draft',
    (tester) async {
      final native = ShareChannelFake()..install();
      addTearDown(native.dispose);
      final repo = ImportRepositoryFake([]);
      final store = RecipeStore(repo, LocalPreferences.memory());
      await store.initialize();
      final drafts = MemoryDraftStorage();
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: AndroidSharePlatform(),
          drafts: drafts,
          importDrafts: MemoryDraftStorage(),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Write a recipe'));
      await tester.pumpAndSettle();
      final editor = tester
          .widget<RecipeEditor>(find.byType(RecipeEditor))
          .controller;
      editor.draft.title = 'Unfinished synthetic soup';
      editor.changed();
      await editor.flush();
      native.queue.add({'text': 'A separate incoming recipe'});
      await native.ready();
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditor), findsOneWidget);
      expect(find.byType(ImportScreen), findsNothing);
      expect((await drafts.read())!['title'], 'Unfinished synthetic soup');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        repo.recipes.values.single.fields.title,
        'Unfinished synthetic soup',
      );
      expect(find.byType(ImportScreen), findsOneWidget);
      expect(find.text('A separate incoming recipe'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'cold cancellation opens queued share before returning to sender',
    (tester) async {
      final native = ShareChannelFake()..install();
      addTearDown(native.dispose);
      native.queue.addAll([
        {'text': 'First shared text', 'coldStart': true},
        {'text': 'Second shared text'},
      ]);
      final repo = ImportRepositoryFake([]);
      final store = RecipeStore(repo, LocalPreferences.memory());
      await store.initialize();
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: AndroidSharePlatform(),
          drafts: MemoryDraftStorage(),
          importDrafts: MemoryDraftStorage(),
          importService: ImportFakeService(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First shared text'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(native.finishes, 0);
      expect(find.text('Second shared text'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(native.finishes, 1);
      expect(repo.imports, 0);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
