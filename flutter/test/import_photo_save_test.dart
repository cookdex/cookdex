import 'dart:io';
import 'dart:typed_data';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakePlatform, ImportFakeService;

class ArchivePlatform extends ImportFakePlatform
    implements ImportPhotoArchivePlatform {
  final saved = <(List<String>, String)>[];
  final discarded = <String>[];
  bool available = true;
  List<int> failures = [];
  @override
  Future<bool> canSavePhotos() async => available;
  @override
  Future<List<int>> savePhotos(List<String> ids, String title) async {
    saved.add((ids, title));
    return failures;
  }

  @override
  Future<void> discardOriginals(List<String> ids) async {
    discarded.addAll(ids);
  }
}

class ArchiveService extends ImportFakeService {
  ArchiveService(this.archive);
  final ArchivePlatform archive;
  @override
  ImportFakePlatform get platform => archive;
}

void main() {
  test('off by default; saves camera and gallery copies after recipe, clear saves nothing', () async {
    final platform = ArchivePlatform();
    final c = ImportController(
      service: ArchiveService(platform),
      storage: MemoryDraftStorage(),
    );
    await c.load();
    c.tab = ImportTab.photos;
    c.photos.addAll([
      ImportPhoto(
        id: 'camera',
        originalId: 'original',
        jpeg: Uint8List.fromList([9]),
      ),
      ImportPhoto(
        id: 'gallery',
        originalId: 'gallery-original',
        jpeg: Uint8List.fromList([8]),
      ),
    ]);
    expect(c.savePhotosToDevice, isFalse);
    await c.saveOriginalsAfterRecipe('Recipe');
    expect(platform.saved, isEmpty);
    c.setSavePhotosToDevice(true);
    expect(platform.saved, isEmpty);
    await c.saveOriginalsAfterRecipe("Mom's Taco Meat");
    expect(platform.saved.single.$1, ['original', 'gallery-original']);
    expect(platform.saved.single.$2, "Mom's Taco Meat");
    await c.clear();
    expect(platform.saved.length, 1);
    expect(platform.discarded, ['original', 'gallery-original']);
    c.dispose();
  });
  test('preference persists and unsupported platforms never save', () async {
    final root = await Directory.systemTemp.createTemp('cookdex-photo-prefs');
    try {
      final path = '${root.path}/prefs.json';
      final prefs = await LocalPreferences.load(path);
      prefs.setSaveImportPhotos(true);
      await prefs.flush();
      final reopened = await LocalPreferences.load(path);
      expect(reopened.saveImportPhotos, isTrue);
      final platform = ArchivePlatform()..available = false;
      final c = ImportController(
        service: ArchiveService(platform),
        storage: MemoryDraftStorage(),
        preferences: reopened,
      );
      await c.load();
      c.tab = ImportTab.photos;
      c.photos.add(
        ImportPhoto(id: 'camera', originalId: 'original', jpeg: Uint8List(0)),
      );
      await c.saveOriginalsAfterRecipe('Recipe');
      expect(platform.saved, isEmpty);
      c.dispose();
      reopened.dispose();
      // dispose queues one last write; drain it before deleting the fixture.
      await reopened.flush();
      prefs.dispose();
      await prefs.flush();
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'missing originals report a partial failure without saving a recipe again',
    () async {
      final platform = ArchivePlatform()..failures = [1];
      final c = ImportController(
        service: ArchiveService(platform),
        storage: MemoryDraftStorage(),
      );
      await c.load();
      c.tab = ImportTab.photos;
      c.setSavePhotosToDevice(true);
      c.photos.add(
        ImportPhoto(id: 'camera', originalId: 'stale', jpeg: Uint8List(0)),
      );
      expect(
        await c.saveOriginalsAfterRecipe('Saved recipe'),
        contains('Recipe saved'),
      );
      c.dispose();
    },
  );
}
