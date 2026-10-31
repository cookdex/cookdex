import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> releaseJson([
  String tag = 'v1.9.1',
  String notes = 'Small improvements.',
]) => {
  'tag_name': tag,
  'draft': false,
  'prerelease': false,
  'published_at': '2026-10-30T12:00:00Z',
  'body': notes,
  'html_url': 'https://untrusted.example/release',
};

class FakeReleaseSource implements ReleaseSource {
  PublishedRelease? result = PublishedRelease.fromJson(releaseJson());
  Object? error;
  Completer<PublishedRelease?>? pending;
  int calls = 0;
  bool closed = false;
  @override
  Future<PublishedRelease?> latest() async {
    calls++;
    if (error != null) throw error!;
    return pending?.future ?? result;
  }

  @override
  void close() {
    closed = true;
  }
}

class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends StreamView<List<int>> implements HttpClientResponse {
  _Response(String body, this.statusCode, {int? length})
    : contentLength = length ?? utf8.encode(body).length,
      super(Stream.value(utf8.encode(body)));
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response);
  final Future<HttpClientResponse> response;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.request);
  final _Request request;
  Uri? uri;
  Object? error;
  bool closed = false;
  @override
  String? userAgent;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    uri = url;
    if (error != null) throw error!;
    return request;
  }

  @override
  void close({bool force = false}) {
    closed = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('version comparison uses major minor patch and ignores v/build', () {
    final current = ReleaseVersion.parse('1.9.0+19000')!;
    for (final (tag, order) in [
      ('v1.9.0', 0),
      ('1.9.0+1', 0),
      ('1.9.1', 1),
      ('1.10.0', 1),
      ('2.0.0', 1),
      ('1.8.99', -1),
      ('0.99.99', -1),
    ]) {
      expect(
        ReleaseVersion.parse(tag)!.compareTo(current).sign,
        order,
        reason: tag,
      );
    }
    for (final tag in [
      '',
      'v1.9',
      '1.9.0-rc.1',
      'V1.9.0',
      '1.09.0',
      ' 1.9.0',
      '1.9.0/../../other',
      'v1.9.0\n',
      '999999999999999999999.0.0',
    ]) {
      expect(ReleaseVersion.parse(tag), isNull, reason: tag);
    }
  });
  test(
    'drafts and prereleases ignored; odd and malformed payloads rejected',
    () {
      expect(
        PublishedRelease.fromJson({...releaseJson(), 'draft': true}),
        isNull,
      );
      expect(
        PublishedRelease.fromJson({...releaseJson(), 'prerelease': true}),
        isNull,
      );
      for (final value in [
        [],
        null,
        {...releaseJson(), 'tag_name': 'latest'},
        {...releaseJson(), 'draft': null},
        {...releaseJson(), 'published_at': 'soon'},
        {...releaseJson(), 'body': 1},
      ]) {
        expect(() => PublishedRelease.fromJson(value), throwsFormatException);
      }
    },
  );
  test(
    'release notes stay exact plain text and only fixed HTTPS repository opens',
    () {
      const notes =
          '<script>alert(1)</script> **bold** [link](https://evil.example)';
      final release = PublishedRelease.fromJson(releaseJson('v1.9.1', notes))!;
      expect(release.notes, 'alert(1) bold link');
      expect(
        release.page.toString(),
        'https://github.com/cookdex/cookdex/releases/tag/v1.9.1',
      );
    },
  );
  test(
    'one anonymous HTTPS request with plain user agent and no redirects',
    () async {
      final request = _Request(
        Future.value(_Response(jsonEncode(releaseJson()), 200)),
      );
      final client = _Client(request);
      final source = GitHubReleaseSource(clientFactory: () => client);
      expect((await source.latest())!.version.toString(), '1.9.1');
      expect(
        client.uri.toString(),
        'https://api.github.com/repos/cookdex/cookdex/releases/latest',
      );
      expect(client.userAgent, 'cookdex-update-checker');
      expect(request.followRedirects, false);
      expect(request.headers.values, {
        'accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2026-03-10',
      });
      expect(client.closed, true);
      source.close();
    },
  );
  for (final code in [301, 403, 429, 500]) {
    test('HTTP $code is a calm failure without retry', () async {
      final client = _Client(_Request(Future.value(_Response('{}', code))));
      final prefs = LocalPreferences.memory();
      final controller = UpdateController(
        preferences: prefs,
        installedVersion: () async => '1.9.0',
        source: GitHubReleaseSource(clientFactory: () => client),
      );
      await controller.check();
      expect(controller.state, UpdateCheckState.error);
      expect(client.closed, true);
      controller.dispose();
      prefs.dispose();
    });
  }
  for (final mode in ['offline', 'timeout', 'invalid JSON', 'oversized']) {
    test('$mode is bounded and safely closed', () async {
      final client = _Client(
        _Request(
          mode == 'timeout'
              ? Completer<HttpClientResponse>().future
              : Future.value(
                  _Response(
                    mode == 'invalid JSON' ? '<html>' : '{}',
                    200,
                    length: mode == 'oversized'
                        ? GitHubReleaseSource.maxResponseBytes + 1
                        : null,
                  ),
                ),
        ),
      );
      if (mode == 'offline') client.error = const SocketException('offline');
      final prefs = LocalPreferences.memory();
      final controller = UpdateController(
        preferences: prefs,
        installedVersion: () async => '1.9.0',
        source: GitHubReleaseSource(
          clientFactory: () => client,
          timeout: const Duration(milliseconds: 10),
        ),
      );
      await controller.check();
      expect(controller.state, UpdateCheckState.error);
      expect(client.closed, true);
      controller.dispose();
      prefs.dispose();
    });
  }
  test(
    'device-only preferences default off and round trip without recipe storage',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'cookdex-update-prefs-',
      );
      final file = File('${dir.path}/ui-preferences.json');
      var prefs = await LocalPreferences.load(file.path);
      expect(prefs.checkUpdatesAutomatically, false);
      expect(prefs.dismissedUpdateVersion, isNull);
      prefs.setCheckUpdatesAutomatically(true);
      prefs.recordUpdateCheck(1234);
      prefs.dismissUpdate('1.9.1');
      await prefs.flush();
      prefs.dispose();
      await prefs.flush();
      prefs = await LocalPreferences.load(file.path);
      expect(prefs.checkUpdatesAutomatically, true);
      expect(prefs.lastUpdateCheckMs, 1234);
      expect(prefs.dismissedUpdateVersion, '1.9.1');
      prefs.dispose();
      await prefs.flush();
      await dir.delete(recursive: true);
    },
  );
  testWidgets(
    'default off does no startup or resume work; manual checks still work',
    (tester) async {
      final prefs = LocalPreferences.memory();
      final source = FakeReleaseSource();
      var versionReads = 0;
      final controller = UpdateController(
        preferences: prefs,
        source: source,
        installedVersion: () async {
          versionReads++;
          return '1.9.0+19000';
        },
      );
      controller.afterFirstFrame();
      await tester.pump(const Duration(days: 3));
      controller.setActive(false);
      controller.setActive(true);
      expect(source.calls, 0);
      expect(versionReads, 0);
      await controller.check();
      expect(controller.state, UpdateCheckState.available);
      expect(controller.notice, isNull);
      source.result = PublishedRelease.fromJson(releaseJson('v1.8.3'));
      await controller.check();
      expect(controller.state, UpdateCheckState.current);
      expect(controller.currentVersion, '1.9.0');
      controller.dispose();
      prefs.dispose();
    },
  );
  testWidgets(
    'automatic delay and daily limit survive restart, failures and resume',
    (tester) async {
      final prefs = LocalPreferences.memory()..checkUpdatesAutomatically = true;
      final source = FakeReleaseSource();
      var now = DateTime.utc(2026, 10, 30);
      UpdateController create() => UpdateController(
        preferences: prefs,
        source: source,
        installedVersion: () async => '1.9.0',
        now: () => now,
      );
      var controller = create();
      controller.afterFirstFrame();
      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(source.calls, 0);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(source.calls, 1);
      expect(controller.notice, isNotNull);
      controller.dispose();
      controller = create();
      controller.afterFirstFrame();
      now = now.add(const Duration(hours: 23));
      await tester.pump(const Duration(hours: 23));
      controller.setActive(false);
      controller.setActive(true);
      expect(source.calls, 1);
      source.error = const SocketException('offline');
      now = now.add(const Duration(hours: 1));
      await tester.pump(const Duration(hours: 1));
      expect(source.calls, 2);
      expect(controller.state, UpdateCheckState.error);
      controller.setActive(false);
      controller.setActive(true);
      await tester.pump();
      expect(source.calls, 2);
      controller.dispose();
      prefs.dispose();
    },
  );
  testWidgets(
    'dismissed version stays hidden until a different version; manual still shows it',
    (tester) async {
      final prefs = LocalPreferences.memory()..checkUpdatesAutomatically = true;
      final source = FakeReleaseSource();
      var now = DateTime.utc(2026, 10, 30);
      final controller = UpdateController(
        preferences: prefs,
        source: source,
        installedVersion: () async => '1.9.0',
        now: () => now,
        startupDelay: Duration.zero,
      );
      controller.afterFirstFrame();
      await tester.pump(const Duration(milliseconds: 1));
      controller.dismissNotice();
      expect(prefs.dismissedUpdateVersion, '1.9.1');
      now = now.add(const Duration(days: 1));
      await tester.pump(const Duration(days: 1));
      expect(controller.notice, isNull);
      await controller.check();
      expect(controller.state, UpdateCheckState.available);
      expect(controller.notice, isNull);
      source.result = PublishedRelease.fromJson(releaseJson('v1.9.2'));
      now = now.add(const Duration(days: 1));
      await tester.pump(const Duration(days: 1));
      expect(controller.notice!.version.toString(), '1.9.2');
      controller.setAutomatic(false);
      expect(controller.notice, isNull);
      controller.dispose();
      prefs.dispose();
    },
  );
  testWidgets(
    'in-flight deduplication and disabling automatic suppresses late notice',
    (tester) async {
      final prefs = LocalPreferences.memory()..checkUpdatesAutomatically = true;
      final source = FakeReleaseSource()
        ..pending = Completer<PublishedRelease?>();
      final controller = UpdateController(
        preferences: prefs,
        source: source,
        installedVersion: () async => '1.9.0',
        startupDelay: Duration.zero,
      );
      controller.afterFirstFrame();
      await tester.pump(const Duration(milliseconds: 1));
      final duplicate = controller.check();
      expect(source.calls, 1);
      controller.setAutomatic(false);
      source.pending!.complete(PublishedRelease.fromJson(releaseJson()));
      await duplicate;
      expect(controller.notice, isNull);
      expect(controller.state, UpdateCheckState.idle);
      controller.dispose();
      prefs.dispose();
    },
  );
}
