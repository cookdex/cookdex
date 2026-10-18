import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'draft_storage.dart';
import 'import_service.dart';
import 'import_page_fetcher.dart';
import 'local_preferences.dart';
import 'src/rust/api.dart' as core;

enum ImportTab { text, link, photos }

/// Owns only selected user input. Never writes a recipe or stores credentials.
class ImportController extends ChangeNotifier {
  ImportController({
    required this.service,
    required this.storage,
    LocalPreferences? preferences,
  }) : preferences = preferences ?? LocalPreferences.memory(),
       _ownsPreferences = preferences == null;
  final ImportService service;
  final DraftStorage storage;
  final LocalPreferences preferences;
  final bool _ownsPreferences;
  ImportTab tab = ImportTab.text;
  String text = '', link = '';
  final List<ImportPhoto> photos = [];
  final List<String> warnings = [];
  String? error;
  bool busy = false, loaded = false, _disposed = false;
  bool canTryWithAi = false;
  int _epoch = 0;
  Future<void> _writes = Future.value();
  bool get hasInput => text.isNotEmpty || link.isNotEmpty || photos.isNotEmpty;
  bool photoSavingAvailable = false;
  bool get savePhotosToDevice => preferences.saveImportPhotos;
  void setSavePhotosToDevice(bool value) {
    preferences.setSaveImportPhotos(value);
    changed();
  }

  Future<String?> saveOriginalsAfterRecipe(String title) async {
    if (!photoSavingAvailable ||
        !savePhotosToDevice ||
        tab != ImportTab.photos) {
      return null;
    }
    final ids = photos.map((p) => p.originalId).nonNulls.toList();
    if (ids.isEmpty) return null;
    busy = true;
    notifyListeners();
    try {
      final failures = await (service.platform as ImportPhotoArchivePlatform)
          .savePhotos(ids, title);
      return failures.isEmpty
          ? null
          : 'Recipe saved, but ${failures.length} photo(s) could not be saved. Originals from a previous app launch are no longer available.';
    } catch (_) {
      return 'Recipe saved, but photos could not be saved to the device.';
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _discardPhotos(Iterable<ImportPhoto> removed) async {
    final platform = service.platform;
    if (platform is ImportPhotoArchivePlatform) {
      await (platform as ImportPhotoArchivePlatform).discardOriginals(
        removed.map((p) => p.originalId).nonNulls.toList(),
      );
    }
  }

  void removePhoto(int index) {
    final photo = photos.removeAt(index);
    unawaited(_discardPhotos([photo]).catchError((Object _) {}));
    changed();
  }

  bool get useAiForLink => preferences.useAiForLink;

  void setUseAiForLink(bool value) {
    preferences.setUseAiForLink(value);
    changed();
  }

  Future<void> load() async {
    try {
      final platform = service.platform;
      if (platform is ImportPhotoArchivePlatform) {
        photoSavingAvailable = await (platform as ImportPhotoArchivePlatform)
            .canSavePhotos();
      }
      final saved = await storage.read();
      if (saved != null) {
        if (saved['version'] != 1) throw const FormatException();
        tab = ImportTab.values.byName(saved['tab'] as String);
        text = saved['text'] as String;
        link = saved['link'] as String;
        photos.addAll(
          (saved['photos'] as List).map(
            (p) => ImportPhoto.fromJson(Map<String, dynamic>.from(p as Map)),
          ),
        );
        warnings.addAll((saved['warnings'] as List? ?? []).cast<String>());
        error = saved['error'] as String?;
      }
    } catch (_) {
      error = 'Could not read the import draft. Clear it to start again.';
    }
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  void changed({bool clearError = true}) {
    if (_disposed) return;
    if (clearError) {
      error = null;
      canTryWithAi = false;
    }
    final value = <String, dynamic>{
      'version': 1,
      'tab': tab.name,
      'text': text,
      'link': link,
      'photos': photos.map((p) => p.toJson()).toList(),
      'warnings': warnings.toList(),
      'error': error,
    };
    _writes = _writes.then((_) async {
      try {
        await storage.write(value);
      } catch (_) {
        error = 'Could not save the import draft.';
        if (!_disposed) notifyListeners();
      }
    });
    notifyListeners();
  }

  Future<void> flush() async {
    await _writes;
    await preferences.flush();
  }

  Future<T?> run<T>(Future<T> Function() action) async {
    if (busy || _disposed) return null;
    final epoch = ++_epoch;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await action();
      return _disposed || epoch != _epoch ? null : result;
    } catch (e) {
      if (!_disposed && epoch == _epoch) {
        error = switch (e) {
          core.ServiceError(:final message) => message,
          StateError(:final message) => message.toString(),
          HttpException(:final message) => message,
          FormatException(:final message) => message,
          PlatformException(:final message) =>
            message ?? 'Import could not be completed. Try again.',
          _ => 'Import could not be completed. Try again.',
        };
        changed(clearError: false);
      }
      return null;
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<ImportDiscovery?> discover({bool? useAi}) async {
    final usedAi = useAi ?? useAiForLink;
    canTryWithAi = false;
    final discovery = await run(
      () => switch (tab) {
        ImportTab.text => service.text(text),
        ImportTab.link => service.link(link, useAi: usedAi),
        ImportTab.photos => service.photos(photos.toList()),
      },
    );
    if (!_disposed && tab == ImportTab.link && !usedAi) {
      canTryWithAi =
          discovery?.canTryWithAi ??
          (error != null && error != insecureImportMessage);
      notifyListeners();
    }
    return discovery;
  }

  Future<core.Candidate?> select(ImportDiscovery discovery, int index) =>
      run(() => service.select(discovery, index));

  Future<void> pickText() async {
    final value = await run(service.platform.pickText);
    if (value != null) {
      text = value;
      changed();
    }
  }

  Future<void> addPhotos({required bool camera}) async {
    final selection = await run(
      () => service.platform.pickPhotos(
        camera: camera,
        maxCount: 8 - photos.length,
      ),
    );
    if (selection == null) return;
    var payload = photos.fold<int>(
      0,
      (sum, photo) => sum + ((photo.jpeg.length + 2) ~/ 3) * 4,
    );
    for (final photo in selection.photos) {
      final bytes = ((photo.jpeg.length + 2) ~/ 3) * 4;
      if (photos.length == 8 || payload + bytes > 12 * 1024 * 1024) {
        warnings.add(
          'A photo was skipped: imports allow 8 photos and 12 MiB of prepared images.',
        );
        await _discardPhotos([photo]);
        continue;
      }
      photos.add(photo);
      payload += bytes;
    }
    warnings.addAll(selection.errors);
    changed();
  }

  void cancel() {
    _epoch++;
    service.cancel();
    busy = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> clear() async {
    cancel();
    await flush();
    await storage.clear();
    text = '';
    link = '';
    await _discardPhotos(photos);
    photos.clear();
    warnings.clear();
    error = null;
    canTryWithAi = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    cancel();
    _disposed = true;
    if (_ownsPreferences) preferences.dispose();
    super.dispose();
  }
}
