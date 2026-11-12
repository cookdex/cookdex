import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'draft_storage.dart';
import 'import_service.dart';
import 'local_preferences.dart';
import 'social_import_page.dart';
import 'youtube_import.dart' show youtubeKeyNeeded;
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
  bool showWebsiteAiHint = false;
  bool canUseManualInput = false;
  ImportDiscovery? linkResult;
  ({String input, String target, SocialSite site})? _resolved;
  bool _confirmedUnknownDuration = false;
  bool _checkingYoutube = false;
  bool? _youtubeHasKey;
  bool _keyReadFailed = false;
  Future<void>? _keyLookup;
  int _keyCheck = 0;
  SocialSite? get linkSite {
    if (tab != ImportTab.link) return null;
    final resolved = _resolved;
    if (resolved != null && resolved.input == link) return resolved.site;
    final uri = Uri.tryParse(link.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return socialSite(uri);
  }

  String? get linkGate {
    final site = linkSite;
    if (site == null) return null;
    if (site != SocialSite.youtube) return blockedLinkMessage(site);
    if (_keyReadFailed) return 'Could not check the Gemini API key.';
    return _youtubeHasKey == false ? youtubeKeyNeeded : null;
  }

  bool get linkUnavailable =>
      linkGate != null ||
      (linkSite == SocialSite.youtube &&
          (_youtubeHasKey != true || linkResult?.fallback == true));

  void checkLinkKey({bool refresh = false}) {
    final youtube = linkSite == SocialSite.youtube;
    if (!refresh && youtube == _checkingYoutube) return;
    _checkingYoutube = youtube;
    final check = ++_keyCheck;
    _youtubeHasKey = null;
    _keyReadFailed = false;
    _keyLookup = null;
    if (!youtube) return;
    _keyLookup = () async {
      try {
        final settings = await service.platform.settings();
        if (_disposed || check != _keyCheck) return;
        _youtubeHasKey = settings.hasKey;
      } catch (_) {
        if (_disposed || check != _keyCheck) return;
        _keyReadFailed = true;
      }
      notifyListeners();
    }();
  }

  String reviewSourceLine = '';
  ImportPhase? phase;
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
        canUseManualInput = saved['manualInput'] == true && error != null;
      }
    } catch (_) {
      error = 'Could not read the import draft. Clear it to start again.';
    }
    checkLinkKey();
    loaded = true;
    if (!_disposed) notifyListeners();
  }

  void changed({bool clearError = true}) {
    if (_disposed) return;
    if (tab != ImportTab.link || _resolved?.input != link) _resolved = null;
    if (clearError) {
      error = null;
      showWebsiteAiHint = false;
      canUseManualInput = false;
      linkResult = null;
      _confirmedUnknownDuration = false;
    }
    checkLinkKey();
    final value = <String, dynamic>{
      'version': 1,
      'tab': tab.name,
      'text': text,
      'link': link,
      'photos': photos.map((p) => p.toJson()).toList(),
      'warnings': warnings.toList(),
      'error': error,
      if (canUseManualInput) 'manualInput': true,
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

  String _errorMessage(Object error) => switch (error) {
    core.ServiceError(:final message) => message,
    StateError(:final message) => message.toString(),
    HttpException(:final message) => message,
    FormatException(:final message) => message,
    PlatformException(:final message) =>
      message ?? 'Import could not be completed. Try again.',
    _ => 'Import could not be completed. Try again.',
  };

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
        error = _errorMessage(e);
        changed(clearError: false);
      }
      return null;
    } finally {
      if (!_disposed && epoch == _epoch) {
        phase = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<ImportDiscovery?> discover({
    bool watchAnyway = false,
    Future<void> Function(bool Function() current)? onReady,
  }) => run(() async {
    final epoch = _epoch;
    bool current() => !_disposed && epoch == _epoch;
    // Plain text starts the recipe operation. Its initial local format probe
    // can finish in a few milliseconds, before the provider request begins.
    var probingText = tab == ImportTab.text && !isCookdexText(text);
    void report(ImportPhase next) {
      if (probingText) {
        probingText = false;
        if (next == ImportPhase.readingText) return;
      }
      if (!current() || next == phase) return;
      phase = next;
      notifyListeners();
    }

    final site = linkSite;
    final requestLink = _resolved?.input == link ? _resolved!.target : link;
    final usedAi = site == SocialSite.youtube || useAiForLink;
    if (site != null) {
      checkLinkKey();
      await _keyLookup;
      if (!current()) throw const ImportCancelled();
      if (linkGate case final message?) {
        return ImportDiscovery(candidates: const [], warnings: [message]);
      }
    }
    final approvedWatch =
        watchAnyway && linkResult?.canWatchAnyway == true ||
        (_confirmedUnknownDuration && linkResult?.canRetryWatch == true);
    _confirmedUnknownDuration = approvedWatch;
    linkResult = null;
    showWebsiteAiHint = false;
    canUseManualInput = false;
    reviewSourceLine = '';
    phase = switch (tab) {
      ImportTab.text =>
        probingText ? ImportPhase.writing : ImportPhase.readingText,
      ImportTab.link => ImportPhase.readingPage,
      ImportTab.photos => ImportPhase.readingPhotos,
    };
    notifyListeners();
    try {
      final discovery = await switch (tab) {
        ImportTab.text => service.text(text, onPhase: report),
        ImportTab.link when approvedWatch && service is YoutubeWatchImport =>
          (service as YoutubeWatchImport).watchAnyway(
            requestLink,
            onPhase: report,
          ),
        ImportTab.link => service.link(
          requestLink,
          useAi: usedAi,
          onPhase: report,
        ),
        ImportTab.photos => service.photos(photos.toList(), onPhase: report),
      };
      if (current()) {
        reviewSourceLine = discovery.sourceLine;
        if (tab == ImportTab.link) {
          linkResult = discovery;
          final source = Uri.tryParse(discovery.source);
          final video = source == null ? null : canonicalYouTubeVideo(source);
          final detected =
              discovery.blockedSite ??
              ((source != null && socialSite(source) == SocialSite.youtube) ||
                      discovery.needsYoutubeKey
                  ? SocialSite.youtube
                  : null);
          if (detected != null) {
            _resolved = (
              input: link,
              target: video?.toString() ?? requestLink,
              site: detected,
            );
            checkLinkKey();
          }
          if (discovery.needsYoutubeKey) {
            _youtubeHasKey = false;
          }
        }
        canUseManualInput =
            tab == ImportTab.link &&
            (discovery.fallback || discovery.candidates.isEmpty);
        showWebsiteAiHint =
            tab == ImportTab.link &&
            site == null &&
            !usedAi &&
            discovery.websiteAiHint;
        if (discovery.candidates.isNotEmpty ||
            discovery.textBlocks.isNotEmpty) {
          await onReady?.call(current);
        }
      }
      return discovery;
    } catch (error) {
      if (current() && tab == ImportTab.link) {
        canUseManualInput = error is! FormatException;
        showWebsiteAiHint =
            site == null && !usedAi && error is! FormatException;
      }
      rethrow;
    }
  });

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
    phase = null;
    busy = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> clearInput() async {
    switch (tab) {
      case ImportTab.text:
        text = '';
      case ImportTab.link:
        link = '';
      case ImportTab.photos:
        final removed = photos.toList();
        photos.clear();
        unawaited(_discardPhotos(removed).catchError((Object _) {}));
        warnings.clear();
    }
    changed();
    await flush();
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
    showWebsiteAiHint = false;
    canUseManualInput = false;
    linkResult = null;
    _resolved = null;
    _confirmedUnknownDuration = false;
    checkLinkKey();
    reviewSourceLine = '';
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
