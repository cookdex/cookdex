import 'dart:async';
import 'dart:io';

import 'package:cookdex/import_link_policy.dart';
import 'package:cookdex/import_page_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends Fake implements HttpClient {
  final requested = <Uri>[];
  final List<String> redirects;
  final bool rejectTls;
  _Client([this.redirects = const [], this.rejectTls = false]);

  @override
  set connectionTimeout(Duration? value) {}
  @override
  set findProxy(String Function(Uri)? value) {}
  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value,
  ) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final hop = requested.length;
    requested.add(url);
    if (rejectTls) throw const HandshakeException('No TLS');
    return _Request(hop < redirects.length ? redirects[hop] : null);
  }

  @override
  void close({bool force = false}) {}
}

class _Request extends Fake implements HttpClientRequest {
  final String? location;
  _Request(this.location);
  @override
  final headers = _Headers();
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() async => _Response(location);
}

class _Headers extends Fake implements HttpHeaders {
  final String? location;
  _Headers([this.location]);
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => location;
  @override
  ContentType get contentType => ContentType.html;
}

class _Response extends Fake implements HttpClientResponse {
  final String? location;
  _Response(this.location);
  @override
  bool get isRedirect => location != null;
  @override
  HttpHeaders get headers => _Headers(location);
  @override
  int get statusCode => isRedirect ? 301 : 200;
  @override
  int get contentLength => 0;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<List<int>>.empty().listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

void main() {
  test('pasted and redirected HTTP URLs upgrade before every GET', () async {
    final client = _Client(['http://recipes.example:80/soup', '/soup/']);
    await HttpOverrides.runZoned(() async {
      final page = await ImportPageFetcher().fetch('http://short.example/r');
      expect(page.url, 'https://recipes.example/soup/');
    }, createHttpClient: (_) => client);
    expect(client.requested.map((u) => u.toString()), [
      'https://short.example/r',
      'https://recipes.example/soup',
      'https://recipes.example/soup/',
    ]);
  });

  test(
    'a website redirect to YouTube returns to the key gate before opening it',
    () async {
      final client = _Client(['https://youtu.be/abcdefghijk']);
      await HttpOverrides.runZoned(() async {
        await expectLater(
          ImportPageFetcher().fetch('https://recipes.example/video'),
          throwsA(isA<YouTubeImportRedirect>()),
        );
      }, createHttpClient: (_) => client);
      expect(client.requested.single.host, 'recipes.example');
    },
  );

  test('failed TLS on an upgraded link never retries over HTTP', () async {
    final client = _Client([], true);
    await HttpOverrides.runZoned(() async {
      await expectLater(
        ImportPageFetcher().fetch('http://recipes.example/soup'),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'TLS error',
            contains('secure connection'),
          ),
        ),
      );
    }, createHttpClient: (_) => client);
    expect(client.requested.single.toString(), 'https://recipes.example/soup');
  });

  test(
    'blocked hosts terminate before the initial GET or redirected GET',
    () async {
      for (final (host, expected) in [
        ('vm.tiktok.com', SocialSite.tiktok),
        ('www.instagram.com', SocialSite.instagram),
        ('threads.net', SocialSite.threads),
        ('www.threads.com', SocialSite.threads),
        ('fb.watch', SocialSite.facebook),
        ('t.co', SocialSite.x),
        ('i.redd.it', SocialSite.reddit),
        ('pin.it', SocialSite.pinterest),
      ]) {
        final blocked = 'http://$host/short';
        for (final redirect in [false, true]) {
          final client = _Client(redirect ? [blocked] : []);
          await HttpOverrides.runZoned(() async {
            await expectLater(
              ImportPageFetcher().fetch(
                redirect ? 'https://recipes.example/soup' : blocked,
              ),
              throwsA(
                isA<BlockedSocialImportUrl>().having(
                  (e) => e.site,
                  'site',
                  expected,
                ),
              ),
            );
          }, createHttpClient: (_) => client);
          expect(
            client.requested.map((u) => u.host),
            redirect ? ['recipes.example'] : isEmpty,
          );
        }
      }
    },
  );

  test(
    'relative redirects remain HTTPS and retain the redirect limit',
    () async {
      final client = _Client(List.filled(6, '/next'));
      await HttpOverrides.runZoned(() async {
        await expectLater(
          ImportPageFetcher().fetch('https://example.com/recipe'),
          throwsA(
            isA<HttpException>().having(
              (e) => e.message,
              'redirect limit',
              'Too many page redirects.',
            ),
          ),
        );
      }, createHttpClient: (_) => client);
      expect(client.requested, hasLength(6));
      expect(client.requested.every((uri) => uri.scheme == 'https'), true);
      expect(client.requested[1].path, '/next');
    },
  );
}
