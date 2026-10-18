import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'import_platform.dart';

/// Reject private/reserved targets, including IPv4-mapped IPv6, before a socket
/// exists. The approved DNS address is also the address actually connected to.
bool isPublicImportAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (b.length == 16) {
    if (b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255) {
      return isPublicImportAddress(
        InternetAddress.fromRawAddress(Uint8List.fromList(b.sublist(12))),
      );
    }
    final first = b[0] * 256 + b[1], second = b[2] * 256 + b[3];
    return (first & 0xe000) == 0x2000 &&
        first != 0x2002 &&
        first != 0x3ffe &&
        first != 0x3fff &&
        !(first == 0x2001 && (second == 0xdb8 || second <= 0x1ff));
  }
  final a = b[0], c = b[1], d = b[2];
  return !(a == 0 ||
      a == 10 ||
      a == 127 ||
      a >= 224 ||
      (a == 169 && c == 254) ||
      (a == 172 && c >= 16 && c <= 31) ||
      (a == 192 && c == 168) ||
      (a == 100 && c >= 64 && c <= 127) ||
      (a == 192 && c == 0 && d <= 2) ||
      (a == 192 && c == 88 && d == 99) ||
      (a == 198 && (c == 18 || c == 19)) ||
      (a == 198 && c == 51 && d == 100) ||
      (a == 203 && c == 0 && d == 113));
}

const insecureImportMessage =
    "This site doesn't use a secure connection. Copy and paste the recipe text instead.";

class InsecureImportUrl extends FormatException {
  const InsecureImportUrl() : super(insecureImportMessage);
}

Uri checkedImportUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri?.scheme == 'http') throw const InsecureImportUrl();
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      input.length > 8192) {
    throw const FormatException('Use a public HTTPS recipe link.');
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  final ip = InternetAddress.tryParse(
    host.replaceAll('[', '').replaceAll(']', ''),
  );
  if ((ip != null && !isPublicImportAddress(ip)) ||
      (ip == null && !host.contains('.')) ||
      [
        '.localhost',
        '.local',
        '.internal',
        '.home',
        '.lan',
      ].any(host.endsWith)) {
    throw const FormatException('Use a public HTTPS recipe link.');
  }
  return uri;
}

class ImportPageFetcher {
  HttpClient? _client;
  int _epoch = 0;
  void cancel() {
    _epoch++;
    _client?.close(force: true);
    _client = null;
  }

  Future<ImportPage> fetch(String input) async {
    final epoch = ++_epoch;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _client = client;
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (epoch != _epoch) throw const HttpException('Cancelled.');
      checkedImportUrl(uri.toString());
      final addresses = await InternetAddress.lookup(
        uri.host.replaceAll('[', '').replaceAll(']', ''),
      ).timeout(const Duration(seconds: 15));
      if (epoch != _epoch ||
          addresses.isEmpty ||
          addresses.any((a) => !isPublicImportAddress(a))) {
        throw const HttpException('Public recipe page required.');
      }
      // A custom connectionFactory replaces HttpClient's TLS setup too.
      // Connect only to checked addresses, then explicitly use the URL hostname
      // for SNI and certificate verification. Try the other family if unreachable.
      Socket? active;
      var cancelled = false;
      final connected = () async {
        Object? lastError;
        for (final address in addresses) {
          if (cancelled || epoch != _epoch) {
            throw const HttpException('Import cancelled.');
          }
          try {
            active = await Socket.connect(
              address,
              uri.port,
              timeout: const Duration(seconds: 5),
            );
            if (cancelled || epoch != _epoch) {
              active!.destroy();
              throw const HttpException('Import cancelled.');
            }
            if (uri.scheme == 'https') {
              active = await SecureSocket.secure(
                active!,
                host: uri.host,
              ).timeout(const Duration(seconds: 8));
            }
            if (cancelled || epoch != _epoch) {
              active!.destroy();
              throw const HttpException('Import cancelled.');
            }
            return active!;
          } catch (error) {
            active?.destroy();
            lastError = error;
            if (error is HandshakeException) rethrow;
          }
        }
        throw lastError ?? const SocketException('No reachable address.');
      }();
      return ConnectionTask.fromSocket(connected, () {
        cancelled = true;
        active?.destroy();
      });
    };
    Future<ImportPage> run() async {
      var uri = checkedImportUrl(input);
      for (var hop = 0; hop <= 5; hop++) {
        if (epoch != _epoch) throw const HttpException('Cancelled.');
        final request = await client.getUrl(uri);
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (compatible; cookdex/0.8; recipe import)',
        );
        request.followRedirects = false;
        request.headers.set(
          HttpHeaders.acceptHeader,
          'text/html,application/xhtml+xml,text/plain',
        );
        final response = await request.close();
        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (hop == 5 || location == null) {
            throw const HttpException('Too many page redirects.');
          }
          uri = checkedImportUrl(uri.resolve(location).toString());
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException(switch (response.statusCode) {
            401 || 403 =>
              'The site blocked the download (HTTP ${response.statusCode}).',
            429 =>
              'The site is limiting downloads. Try again later (HTTP 429).',
            404 || 410 =>
              'The recipe page was not found (HTTP ${response.statusCode}).',
            _ =>
              'The site returned HTTP ${response.statusCode}. Try again later.',
          });
        }
        if (![
          'text/html',
          'application/xhtml+xml',
          'text/plain',
        ].contains(response.headers.contentType?.mimeType)) {
          throw const HttpException('The link did not return a recipe page.');
        }
        const limit = 5 * 1024 * 1024;
        if (response.contentLength > limit) {
          throw const HttpException('Recipe page exceeds 5 MiB.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response) {
          if (epoch != _epoch || bytes.length + chunk.length > limit) {
            throw const HttpException(
              'Recipe page exceeds 5 MiB or was cancelled.',
            );
          }
          bytes.add(chunk);
        }
        return ImportPage(
          html: utf8.decode(bytes.takeBytes()),
          url: uri.toString(),
        );
      }
      throw const HttpException('Recipe page unavailable.');
    }

    try {
      return await run().timeout(const Duration(seconds: 25));
    } on FormatException {
      rethrow;
    } on HandshakeException {
      throw const HttpException(
        'The site’s secure connection or certificate could not be verified.',
      );
    } on TimeoutException {
      throw const HttpException('The recipe download timed out. Try again.');
    } on SocketException catch (error) {
      throw HttpException(
        error.message.contains('Failed host lookup')
            ? 'The site’s address could not be found (DNS). Check the link and connection.'
            : 'The site could not be reached. Check your connection and try again.',
      );
    } on HttpException {
      rethrow;
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }
}
