import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/app_platform.dart';
import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show EditorFake;
import 'recipe_store_test.dart' show recipe;

Candidate candidate(String id, String title) => Candidate(
  recipe: recipe(id, title: title),
  warnings: const [],
  ingredientSources: const [],
);

class ImportFakePlatform implements ImportPlatform {
  String? text;
  PhotoSelection selection = const PhotoSelection(photos: []);
  @override
  Future<SmartImportSettings> settings() async =>
      const SmartImportSettings(hasKey: false, model: 'test-model');
  @override
  Future<void> saveSettings({
    required String key,
    required String model,
  }) async {}
  @override
  Future<void> removeKey() async {}
  @override
  Future<String?> pickText() async => text;
  @override
  Future<PhotoSelection> pickPhotos({
    required bool camera,
    required int maxCount,
  }) async => selection;
  @override
  Future<ImportPage> fetchPage(String url) async => throw UnimplementedError();
  @override
  Future<ProviderReply> providerRequest(Uint8List body) async =>
      throw UnimplementedError();
  @override
  Future<void> cancel() async {}
}

class ShellPlatform extends AppPlatform {
  @override
  bool get isAndroid => false;
  @override
  Future<void> backgroundTask() async {}
  @override
  Future<void> openSource(String url) async {}
  @override
  Future<Uint8List?> pickRecipeZip() async => null;
  @override
  Future<String> privateRoot() async => throw UnimplementedError();
  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
  @override
  Future<ColorScheme?> wallpaperColorScheme({
    Brightness brightness = Brightness.dark,
  }) async => null;
}

class ImportFakeService implements ImportService {
  @override
  final ImportFakePlatform platform = ImportFakePlatform();
  ImportDiscovery result = ImportDiscovery(
    candidates: [
      candidate('one', 'First recipe'),
      candidate('two', 'Second recipe'),
    ],
  );
  Completer<ImportDiscovery>? pending;
  String? received;
  int? selected;
  int cancelled = 0;
  @override
  Future<ImportDiscovery> text(String value) async {
    received = value;
    return pending == null ? result : pending!.future;
  }

  @override
  Future<ImportDiscovery> link(String value, {bool useAi = false}) async {
    received = value;
    return result;
  }

  @override
  Future<ImportDiscovery> photos(List<ImportPhoto> photos) async => result;
  @override
  Future<Candidate> select(ImportDiscovery discovery, int index) async {
    selected = index;
    return discovery.candidates[index];
  }

  @override
  Future<String> prompt() async => 'Keep quantities exactly as written.';
  @override
  void cancel() {
    cancelled++;
  }
}

class ImportRepositoryFake extends EditorFake
    implements ImportRecipeRepository {
  ImportRepositoryFake(super.recipes);
  DuplicateChoice? choice;
  int imports = 0;
  @override
  Future<CollectionSnapshot> importOne(
    int generation,
    RecipeFields fields,
    DuplicateChoice? choice,
  ) async {
    if (generation != current.generation) {
      throw const ServiceError(
        code: ErrorCode.staleWrite,
        message: 'Recipes changed. Review again.',
      );
    }
    this.choice = choice;
    imports++;
    return save(
      generation,
      choice is DuplicateChoice_Replace ? recipes[choice.id] : null,
      fields,
    );
  }
}

void main() {
  testWidgets('Import fits a narrow large-text screen across all tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = ImportController(
      service: ImportFakeService(),
      storage: MemoryDraftStorage(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: ImportScreen(controller: c, onReview: (_, _) async => null),
      ),
    );
    await tester.pumpAndSettle();
    for (final tab in ImportTab.values) {
      c.tab = tab;
      c.changed();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('actionable import errors keep input and persist for retry', () async {
    final storage = MemoryDraftStorage();
    final c = ImportController(service: ImportFakeService(), storage: storage);
    c.link = 'https://example.test/blocked';
    await c.run<void>(
      () async => throw const HttpException(
        'Page access was blocked. Paste recipe text instead.',
      ),
    );
    expect(c.error, 'Page access was blocked. Paste recipe text instead.');
    expect(c.link, 'https://example.test/blocked');
    await c.flush();
    expect((await storage.read())!['error'], c.error);
    await c.run<void>(
      () async => throw StateError('Add a Gemini key to use AI import.'),
    );
    expect(c.error, 'Add a Gemini key to use AI import.');
    c.dispose();
  });
  testWidgets(
    'resuming an unrelated editor draft keeps the pending import source',
    (tester) async {
      final repository = ImportRepositoryFake([]);
      final store = RecipeStore(repository, LocalPreferences.memory());
      await store.initialize();
      final drafts = MemoryDraftStorage();
      await drafts.write(
        EditorDraft(title: 'Older unfinished recipe').toJson(),
      );
      final inputs = MemoryDraftStorage();
      final service = ImportFakeService()
        ..result = ImportDiscovery(
          candidates: [candidate('incoming', 'New import')],
        );
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: ShellPlatform(),
          drafts: drafts,
          importDrafts: inputs,
          importService: service,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smart Import'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'new source text');
      await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await tester.pumpAndSettle();
      expect(find.text('Resume draft?'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(ImportScreen), findsOneWidget);
      expect(find.text('new source text'), findsOneWidget);
      expect((await inputs.read())!['text'], 'new source text');
      expect(repository.imports, 0);
      expect(
        repository.recipes.values.single.fields.title,
        'Older unfinished recipe',
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
  test('import inputs, photos, warnings and errors persist independently of editor', () async {
    final storage = MemoryDraftStorage();
    final c = ImportController(service: ImportFakeService(), storage: storage);
    await c.load();
    c.text = 'raw text';
    c.link = 'https://example.test/recipe';
    c.tab = ImportTab.photos;
    c.photos.add(ImportPhoto(id: 'photo', jpeg: Uint8List.fromList([1, 2, 3])));
    c.error = 'offline';
    c.warnings.add('Unreadable photo skipped');
    c.changed(clearError: false);
    await c.flush();
    c.dispose();
    final recovered = ImportController(
      service: ImportFakeService(),
      storage: storage,
    );
    await recovered.load();
    expect(recovered.text, 'raw text');
    expect(recovered.link, 'https://example.test/recipe');
    expect(recovered.tab, ImportTab.photos);
    expect(recovered.photos.single.jpeg, [1, 2, 3]);
    expect(recovered.error, 'offline');
    expect(recovered.warnings, ['Unreadable photo skipped']);
    await recovered.clear();
    expect(await storage.read(), isNull);
    recovered.dispose();
  });
  test('cancel ignores late discovery and preserves user input', () async {
    final service = ImportFakeService()..pending = Completer<ImportDiscovery>();
    final c = ImportController(service: service, storage: MemoryDraftStorage());
    c.text = 'selected text';
    c.link = 'unselected private link';
    final pending = c.discover();
    c.cancel();
    service.pending!.complete(service.result);
    expect(await pending, isNull);
    expect(service.received, 'selected text');
    expect(c.text, 'selected text');
    expect(c.busy, false);
    c.dispose();
  });
  test('partial photo additions retain successes and expose errors', () async {
    final service = ImportFakeService();
    service.platform.selection = PhotoSelection(
      photos: [ImportPhoto(id: 'ok', jpeg: Uint8List(1))],
      errors: ['Bad image skipped'],
    );
    final c = ImportController(service: service, storage: MemoryDraftStorage());
    await c.addPhotos(camera: false);
    expect(c.photos.single.id, 'ok');
    expect(c.warnings.single, 'Bad image skipped');
    c.dispose();
  });
  test('import editor has no base, survives recovery, requires explicit duplicate choice', () async {
    final repository = ImportRepositoryFake([
      recipe('existing', title: '  FIRST   recipe '),
    ]);
    final store = RecipeStore(repository, LocalPreferences.memory());
    await store.initialize();
    final storage = MemoryDraftStorage();
    final c = await EditorController.create(
      store: store,
      storage: storage,
      imported: Candidate(
        recipe: recipe('incoming', title: 'First recipe'),
        warnings: const [],
        ingredientSources: const [],
        aiReview: AiReview(
          guessedFields: const ['servings', 'totalTime', 'tags'],
          guessedSteps: Uint32List.fromList([0]),
        ),
      ),
    );
    expect(c.draft.base, isNull);
    expect(c.draft.imported, true);
    expect(repository.imports, 0);
    await c.flush();
    final savedDraft = await storage.read();
    expect(savedDraft!['imported'], true);
    final recovered = EditorDraft.fromJson(savedDraft);
    expect(recovered.aiGuessedFields, {'servings', 'totalTime', 'tags'});
    expect(recovered.steps.first.aiGuess, true);
    final guessed = recovered.steps.first;
    c.reorder(c.draft.steps, 0, c.draft.steps.length - 1);
    expect(c.draft.steps.any((s) => s.aiGuess), true);
    expect(guessed.aiGuess, true);
    expect(await c.save(chooseDuplicate: (_) async => null), isNull);
    expect(repository.imports, 0);
    final saved = await c.save(
      chooseDuplicate: (duplicates) async {
        expect(duplicates.single.id, 'existing');
        return const DuplicateChoice.replace(id: 'existing');
      },
    );
    expect(saved!.id, 'existing');
    expect(repository.imports, 1);
    expect(c.draft.aiGuessedFields, isEmpty);
    expect(c.draft.steps.any((s) => s.aiGuess), false);
    expect(saved.createdAt, repository.savedBase!.createdAt);
    expect(saved.revision, repository.savedBase!.revision + 1);
    c.dispose();
    store.dispose();
  });
  test(
    'duplicate keep both and stale choice never overwrite a changed recipe',
    () async {
      final repository = ImportRepositoryFake([
        recipe('existing', title: 'First recipe'),
      ]);
      final store = RecipeStore(repository, LocalPreferences.memory());
      await store.initialize();
      final c = await EditorController.create(
        store: store,
        storage: MemoryDraftStorage(),
        imported: candidate('incoming', 'First recipe'),
      );
      final saved = await c.save(
        chooseDuplicate: (_) async => const DuplicateChoice.keepBoth(),
      );
      expect(saved!.id, isNot('existing'));
      expect(repository.recipes.length, 2);
      c.dispose();
      final stale = await EditorController.create(
        store: store,
        storage: MemoryDraftStorage(),
        imported: candidate('incoming', 'First recipe'),
      );
      final rejected = await stale.save(
        chooseDuplicate: (_) async {
          await store.toggleFavorite('existing');
          return const DuplicateChoice.replace(id: 'existing');
        },
      );
      expect(rejected, isNull);
      expect(stale.draft.error, contains('changed'));
      expect(repository.imports, 1);
      stale.dispose();
      store.dispose();
    },
  );
  testWidgets(
    'multiple candidates require one choice and open only selected review',
    (tester) async {
      final service = ImportFakeService();
      final c = ImportController(
        service: service,
        storage: MemoryDraftStorage(),
      );
      final reviewed = <Candidate>[];
      final original = service.result.candidates.last;
      service.result = ImportDiscovery(
        candidates: [
          service.result.candidates.first,
          Candidate(
            recipe: original.recipe,
            warnings: original.warnings,
            ingredientSources: original.ingredientSources,
            aiReview: AiReview(
              guessedFields: const ['totalTime'],
              guessedSteps: Uint32List.fromList([0]),
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: ImportScreen(
            controller: c,
            onReview: (_, candidate) async {
              reviewed.add(candidate);
              return null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'recipes');
      await tester.tap(find.widgetWithText(FilledButton, 'Smart Import'));
      await tester.pumpAndSettle();
      expect(find.text('Choose one recipe'), findsOneWidget);
      expect(reviewed, isEmpty);
      await tester.tap(find.text('Second recipe'));
      await tester.pumpAndSettle();
      expect(reviewed.single.recipe.id, 'two');
      expect(reviewed.single.aiReview!.guessedFields, ['totalTime']);
      expect(reviewed.single.aiReview!.guessedSteps, [0]);
      expect(service.selected, 1);
      expect(c.text, 'recipes');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
