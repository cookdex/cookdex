import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'local_preferences.dart';
import 'release_notes.dart';

const updateCheckError = "Couldn't check for updates right now.";

class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion._(this.major, this.minor, this.patch);
  final int major, minor, patch;

  static ReleaseVersion? parse(String text) {
    if (text.length > 80) return null;
    final match = RegExp(
      r'^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
    ).firstMatch(text);
    if (match == null) return null;
    final numbers = [for (var i = 1; i <= 3; i++) int.tryParse(match[i]!)];
    if (numbers.any((n) => n == null)) return null;
    return ReleaseVersion._(numbers[0]!, numbers[1]!, numbers[2]!);
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final comparison = a.compareTo(b);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  @override
  String toString() => '$major.$minor.$patch';
}

class PublishedRelease {
  const PublishedRelease._(this.version, this.notes, this.page);
  final ReleaseVersion version;
  final String notes;
  final Uri page;

  static PublishedRelease? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) throw const FormatException();
    if (value['draft'] == true || value['prerelease'] == true) return null;
    final tag = value['tag_name'];
    final published = value['published_at'];
    final body = value['body'];
    final version = tag is String ? ReleaseVersion.parse(tag) : null;
    if (value['draft'] != false ||
        value['prerelease'] != false ||
        version == null ||
        published is! String ||
        DateTime.tryParse(published) == null ||
        (body != null && body is! String)) {
      throw const FormatException();
    }
    // Never use html_url, assets, or links embedded in untrusted release notes.
    return PublishedRelease._(
      version,
      plainReleaseNotes(body as String? ?? ''),
      Uri.https('github.com', '/cookdex/cookdex/releases/tag/$tag'),
    );
  }
}

abstract interface class ReleaseSource {
  Future<PublishedRelease?> latest();
  void close();
}

class GitHubReleaseSource implements ReleaseSource {
  GitHubReleaseSource({
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 10),
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  final HttpClient Function() _clientFactory;
  final Duration timeout;
  final _clients = <HttpClient>{};
  bool _closed = false;
  static final endpoint = Uri.https(
    'api.github.com',
    '/repos/cookdex/cookdex/releases/latest',
  );
  static const maxResponseBytes = 256 * 1024;

  @override
  Future<PublishedRelease?> latest() async {
    if (_closed) throw StateError('Closed');
    final client = _clientFactory()
      ..userAgent = 'cookdex-update-checker'
      ..connectionTimeout = timeout;
    _clients.add(client);
    try {
      return await _read(client).timeout(timeout);
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<PublishedRelease?> _read(HttpClient client) async {
    final request = await client.getUrl(endpoint);
    request.followRedirects = false;
    request.headers.set(
      HttpHeaders.acceptHeader,
      'application/vnd.github+json',
    );
    request.headers.set('X-GitHub-Api-Version', '2026-03-10');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > maxResponseBytes) {
      throw const FormatException();
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        throw const FormatException();
      }
      bytes.add(chunk);
    }
    return PublishedRelease.fromJson(
      jsonDecode(utf8.decode(bytes.takeBytes())),
    );
  }

  @override
  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

enum UpdateCheckState { idle, checking, current, available, error }

class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.preferences,
    required this.installedVersion,
    ReleaseSource? source,
    DateTime Function()? now,
    this.startupDelay = const Duration(seconds: 5),
  }) : _source = source ?? GitHubReleaseSource(),
       _now = now ?? DateTime.now {
    preferences.addListener(_preferencesChanged);
  }
  final LocalPreferences preferences;
  final Future<String> Function() installedVersion;
  final ReleaseSource _source;
  final DateTime Function() _now;
  final Duration startupDelay;
  static const interval = Duration(days: 1);
  UpdateCheckState state = UpdateCheckState.idle;
  String? currentVersion;
  PublishedRelease? release, notice;
  Timer? _daily;
  DateTime? _startupDeadline;
  bool _ready = false, _active = true, _disposed = false;
  int _automaticGeneration = 0;
  Future<void>? _flight;

  /// Called after the first app frame, with no awaited work on startup's path.
  void afterFirstFrame() {
    if (_disposed || _ready) return;
    _ready = true;
    _startupDeadline = _now().add(startupDelay);
    _schedule();
  }

  void setActive(bool active) {
    _active = active;
    _schedule();
  }

  void setAutomatic(bool enabled) =>
      preferences.setCheckUpdatesAutomatically(enabled);

  void _preferencesChanged() {
    if (!preferences.checkUpdatesAutomatically) {
      _automaticGeneration++;
      notice = null;
    }
    _schedule();
    if (!_disposed) notifyListeners();
  }

  void _schedule() {
    _daily?.cancel();
    _daily = null;
    if (_disposed ||
        !_ready ||
        !_active ||
        !preferences.checkUpdatesAutomatically) {
      return;
    }
    final last = preferences.lastUpdateCheckMs;
    final elapsed = last == null
        ? interval.inMilliseconds
        : _now().toUtc().millisecondsSinceEpoch - last;
    // Clock rollback never creates a burst of requests. Re-evaluate daily.
    final dailyWait = (interval.inMilliseconds - elapsed).clamp(
      0,
      interval.inMilliseconds,
    );
    final startupWait = _startupDeadline!.difference(_now()).inMilliseconds;
    final wait = startupWait > dailyWait ? startupWait : dailyWait;
    _daily = Timer(Duration(milliseconds: wait), () {
      unawaited(check(automatic: true));
    });
  }

  Future<void> check({bool automatic = false}) {
    if (_disposed) return Future.value();
    if (_flight case final pending?) return pending;
    if (automatic &&
        (!_ready || !_active || !preferences.checkUpdatesAutomatically)) {
      return Future.value();
    }
    if (automatic && _now().isBefore(_startupDeadline!)) {
      _schedule();
      return Future.value();
    }
    final last = preferences.lastUpdateCheckMs;
    if (automatic &&
        last != null &&
        _now().toUtc().millisecondsSinceEpoch - last <
            interval.inMilliseconds) {
      _schedule();
      return Future.value();
    }
    final completion = Completer<void>();
    _flight = completion.future;
    unawaited(
      _check(automatic, _automaticGeneration).whenComplete(() {
        _flight = null;
        _schedule();
        completion.complete();
      }),
    );
    return completion.future;
  }

  Future<void> _check(bool automatic, int generation) async {
    state = UpdateCheckState.checking;
    notifyListeners();
    try {
      // Persist attempts, including errors, so a restart cannot bypass the limit.
      preferences.recordUpdateCheck(_now().toUtc().millisecondsSinceEpoch);
      await preferences.flush();
      if (_disposed || (automatic && generation != _automaticGeneration)) {
        return;
      }
      if (preferences.persistenceError != null) {
        throw StateError('Preferences unavailable');
      }
      final installed = ReleaseVersion.parse(
        await installedVersion().timeout(const Duration(seconds: 10)),
      );
      if (installed == null) throw const FormatException();
      if (_disposed || (automatic && generation != _automaticGeneration)) {
        return;
      }
      final result = await _source.latest();
      if (_disposed || (automatic && generation != _automaticGeneration)) {
        return;
      }
      if (result == null) throw const FormatException();
      currentVersion = installed.toString();
      release = result.version.compareTo(installed) > 0 ? result : null;
      state = release == null
          ? UpdateCheckState.current
          : UpdateCheckState.available;
      if (automatic) {
        notice =
            release?.version.toString() == preferences.dismissedUpdateVersion
            ? null
            : release;
      } else if (notice != null) {
        notice =
            release?.version.toString() == preferences.dismissedUpdateVersion
            ? null
            : release;
      }
    } catch (_) {
      if (!_disposed && (!automatic || generation == _automaticGeneration)) {
        state = UpdateCheckState.error;
        release = null;
      }
    } finally {
      if (!_disposed) {
        if (state == UpdateCheckState.checking) state = UpdateCheckState.idle;
        notifyListeners();
      }
    }
  }

  void dismissNotice() {
    if (notice case final found?) {
      preferences.dismissUpdate(found.version.toString());
      notice = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _daily?.cancel();
    preferences.removeListener(_preferencesChanged);
    _source.close();
    super.dispose();
  }
}
