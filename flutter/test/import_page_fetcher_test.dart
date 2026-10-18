import 'dart:io';

import 'package:cookdex/import_page_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends Fake implements HttpClient {
  final requested = <Uri>[];
  final String location;
  _Client(this.location);

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
    requested.add(url);
    return _Request(location);
  }

  @override
  void close({bool force = false}) {}
}

class _Request extends Fake implements HttpClientRequest {
  final String location;
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
}

class _Response extends Fake implements HttpClientResponse {
  final String location;
  _Response(this.location);
  @override
  bool get isRedirect => true;
  @override
  HttpHeaders get headers => _Headers(location);
}

void main() {
  test('HTTP initial URL is rejected before any request', () async {
    final client = _Client('/unused');
    await HttpOverrides.runZoned(() async {
      await expectLater(
        ImportPageFetcher().fetch('http://example.com/recipe'),
        throwsA(
          isA<InsecureImportUrl>().having(
            (e) => e.message,
            'friendly guidance',
            insecureImportMessage,
          ),
        ),
      );
    }, createHttpClient: (_) => client);
    expect(client.requested, isEmpty);
  });

  test('HTTPS downgrade is rejected before a second request', () async {
    final client = _Client('http://example.com/insecure');
    await HttpOverrides.runZoned(() async {
      await expectLater(
        ImportPageFetcher().fetch('https://example.com/recipe'),
        throwsA(isA<InsecureImportUrl>()),
      );
    }, createHttpClient: (_) => client);
    expect(client.requested.map((uri) => uri.toString()), [
      'https://example.com/recipe',
    ]);
  });

  test(
    'relative redirects remain HTTPS and retain the redirect limit',
    () async {
      final client = _Client('/next');
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
