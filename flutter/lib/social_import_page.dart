import 'dart:convert';

import 'import_link_policy.dart';

export 'import_link_policy.dart';

/// Returns only a single HTTPS video, discarding playlists, time and tracking.
Uri? canonicalYouTubeVideo(Uri uri) {
  if (socialSite(uri) != SocialSite.youtube ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443) {
    return null;
  }
  final host = uri.host.replaceFirst(RegExp(r'\.$'), '');
  final id = switch ((host, uri.pathSegments)) {
    ('youtu.be' || 'www.youtu.be', [final id]) => id,
    (
      'youtube.com' ||
          'www.youtube.com' ||
          'm.youtube.com' ||
          'music.youtube.com',
      final path,
    ) =>
      switch (path) {
        ['watch'] when uri.queryParametersAll['v']?.length == 1 =>
          uri.queryParameters['v'],
        ['shorts', final id] || ['embed', final id] || ['live', final id] => id,
        _ => null,
      },
    _ => null,
  };
  if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) return null;
  return Uri.https('www.youtube.com', '/watch', {'v': id});
}

/// A redirect may normalize the URL, but must still identify the shared video.
bool matchesSocialPostRedirect(Uri original, Uri finalUri) {
  final video = canonicalYouTubeVideo(original);
  return video != null && video == canonicalYouTubeVideo(finalUri);
}

class SocialImportPage {
  const SocialImportPage._({
    this.title = '',
    this.text = '',
    this.videoUrl,
    this.seconds,
    this.blocked = false,
    this.nonPublic = false,
    this.unconfirmedVisibility = false,
  });

  final String title, text;
  final Uri? videoUrl;
  final int? seconds;
  final bool blocked, nonPublic, unconfirmedVisibility;

  factory SocialImportPage.parse(SocialSite site, Uri uri, String html) {
    if (site != SocialSite.youtube || _wallPath(uri)) {
      return const SocialImportPage._(blocked: true);
    }
    final identity = canonicalYouTubeVideo(uri);
    if (identity == null) return const SocialImportPage._(blocked: true);
    final page = _Markup(html, readPlayer: true);
    if (page.wall) return const SocialImportPage._(blocked: true);
    return _youtubePage(identity, page);
  }
}

SocialImportPage _youtubePage(Uri identity, _Markup page) {
  final player = _object(page.playerJson);
  final status = _map(player['playabilityStatus']);
  final details = _map(player['videoDetails']);
  final micro = _map(_map(player['microformat'])['playerMicroformatRenderer']);
  final nonPublic =
      details['isPrivate'] == true ||
      micro['isUnlisted'] == true ||
      _privateVideo.hasMatch(_string(status['reason']));
  final id = identity.queryParameters['v'];
  if (nonPublic ||
      (status['status'] != null && status['status'] != 'OK') ||
      (details['videoId'] != null && details['videoId'] != id) ||
      (micro['externalVideoId'] != null && micro['externalVideoId'] != id) ||
      details['isLive'] == true ||
      details['isUpcoming'] == true) {
    return SocialImportPage._(blocked: true, nonPublic: nonPublic);
  }
  final matchesPlayer = status['status'] == 'OK' && details['videoId'] == id;
  final length = matchesPlayer
      ? int.tryParse('${details['lengthSeconds']}')
      : null;
  if (!matchesPlayer || micro['isUnlisted'] != false) {
    // A matching player's known duration still enforces the watching limit.
    return SocialImportPage._(
      videoUrl: identity,
      seconds: length,
      unconfirmedVisibility: true,
    );
  }
  return SocialImportPage._(
    title: _string(details['title']),
    text: _string(details['shortDescription']),
    videoUrl: identity,
    seconds: length != null && length > 0 ? length : null,
  );
}

final _privateVideo = RegExp(
  r'\b(?:private|unlisted) video\b|\bvideo is (?:private|unlisted)\b',
  caseSensitive: false,
);

String _string(Object? value) => value is String ? value : '';
Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : const {};
Map<String, dynamic> _object(String source) {
  if (source.isEmpty) return const {};
  try {
    return _map(jsonDecode(source));
  } on FormatException {
    return const {};
  }
}

bool _wallPath(Uri uri) =>
    uri.host.startsWith('consent.') ||
    uri.host.startsWith('accounts.') ||
    RegExp(
      r'/(?:login(?:\.php)?|signin|checkpoint|consent|challenge|captcha|authwall)(?:/|$)',
      caseSensitive: false,
    ).hasMatch(uri.path);

bool isImportAccessWall(Uri uri, String html) =>
    _wallPath(uri) || _Markup(html).wall;

final _tagStart = RegExp(r'<!--|<(/?)([a-zA-Z][a-zA-Z0-9:_-]*)\b');
final _attribute = RegExp(
  r'''([^\s="'/<>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>\x60]+)))?''',
);
final _playerAssignment = RegExp(
  r'\s*(?:(?:var|let|const)\s+|window\.)?ytInitialPlayerResponse\s*=\s*',
);
final _wallMessage = RegExp(
  r'\b(?:before you continue to|verify (?:that )?you are human|checking your browser|'
  r'access denied|you(?: have been|.ve been) blocked by network security|'
  r'log ?in (?:is required|to (?:view|watch|continue|read|see this))|'
  r'sign in (?:is required|to (?:view|watch|continue|read|confirm|see this))|'
  r'sign up to (?:view|watch|continue|read|see this)|consent required|'
  r'(?:a subscription|membership) is required|subscribe to (?:continue reading|read (?:this|the full))|'
  r'(?:you (?:must|need to)|please) (?:log ?in|sign in) to|'
  r'(?:enable|turn on) javascript (?:and cookies )?to continue|'
  r'(?:this (?:content|post|video|account)|this page) is (?:private|unlisted|unavailable|not available)|'
  r'private video|unlisted video|video unavailable|this video has been removed|'
  r'accept (?:all )?cookies to (?:view|continue|access))\b',
  caseSensitive: false,
);
final _wallTitle = RegExp(
  r'^\s*(?:log ?in|sign in|just a moment|security check|access denied|captcha|page not found|please wait|something went wrong)\b',
  caseSensitive: false,
);
final _blockTags = {
  'p',
  'br',
  'div',
  'li',
  'article',
  'section',
  'h1',
  'h2',
  'h3',
  'main',
  'header',
  'footer',
  'td',
  'tr',
};
final _rawEnds = {
  for (final tag in ['script', 'style', 'template', 'noscript', 'svg'])
    tag: RegExp('</$tag\\s*>', caseSensitive: false),
};

// Inspect visible text for access walls. Only the signed-out YouTube player
// assignment supplies video metadata; scripts never supply ordinary page text.
class _Markup {
  final meta = <String, String>{};
  String title = '', playerJson = '';
  bool wall = false;

  _Markup(String html, {bool readPlayer = false}) {
    final visible = StringBuffer(), heading = StringBuffer();
    var cursor = 0, inTitle = false;
    var password = false, loginForm = false;
    void append(int end) {
      if (end <= cursor) return;
      if (visible.length >= 6000 && !inTitle) return;
      final part = _entities(html.substring(cursor, end));
      if (inTitle) {
        heading.write(part);
      } else if (visible.length < 6000) {
        visible.write(part);
      }
    }

    while (cursor < html.length) {
      final start = html.indexOf(_tagStart, cursor);
      if (start < 0) {
        append(html.length);
        break;
      }
      append(start);
      if (html.startsWith('<!--', start)) {
        final end = html.indexOf('-->', start + 4);
        cursor = end < 0 ? html.length : end + 3;
        continue;
      }
      final tag = _tagStart.matchAsPrefix(html, start)!;
      final name = tag[2]!.toLowerCase();
      final end = _tagEnd(html, tag.end);
      if (end < 0) break;
      cursor = end + 1;
      final closing = tag[1] == '/';
      if (name == 'title') inTitle = !closing && heading.isEmpty;
      if (_blockTags.contains(name) && visible.length < 6000) {
        visible.write('\n');
      }
      if (closing) continue;
      final rawEnd = _rawEnds[name];
      if (rawEnd != null) {
        final closeStart = html.indexOf(rawEnd, cursor);
        if (closeStart < 0) break;
        if (name == 'script' && readPlayer && playerJson.isEmpty) {
          final assignment = _playerAssignment.matchAsPrefix(html, cursor);
          if (assignment != null && assignment.end < closeStart) {
            playerJson = _playerObject(html, assignment.end, closeStart);
          }
        }
        cursor = rawEnd.matchAsPrefix(html, closeStart)!.end;
        continue;
      }
      if (name == 'meta' || name == 'input' || name == 'form') {
        final attrs = _attributes(html.substring(tag.end, end));
        if (name == 'meta') {
          final key = (attrs['property'] ?? attrs['name'] ?? '').toLowerCase();
          final value = attrs['content'] ?? '';
          if ((key == 'og:title' ||
                  (readPlayer &&
                      (key == 'og:description' || key == 'description'))) &&
              value.isNotEmpty) {
            meta.putIfAbsent(key, () => value);
          }
        } else if (name == 'input') {
          if (attrs['name'] == 'js_challenge' ||
              attrs['name'] == 'cf-turnstile-response') {
            wall = true;
          }
          if (attrs['type']?.toLowerCase() == 'password') password = true;
        } else if (_wallPath(Uri.tryParse(attrs['action'] ?? '') ?? Uri()) ||
            attrs['id'] == 'challenge-form') {
          loginForm = true;
          if (attrs['id'] == 'challenge-form') wall = true;
        }
      }
    }
    title = heading.toString().trim();
    final body = visible.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    wall =
        wall ||
        (password && loginForm) ||
        _wallTitle.hasMatch(title) ||
        _wallMessage.hasMatch(title) ||
        _wallMessage.hasMatch(body) ||
        (readPlayer && meta.values.any(_wallMessage.hasMatch));
  }
}

// Isolate the player object when the same script continues with other setup.
// Braces inside a quoted description never terminate the object.
String _playerObject(String html, int start, int end) {
  if (html.codeUnitAt(start) != 123) return '';
  var depth = 0, inString = false;
  for (var i = start; i < end; i++) {
    final char = html.codeUnitAt(i);
    if (inString) {
      if (char == 92) {
        i++;
      } else if (char == 34) {
        inString = false;
      }
    } else if (char == 34) {
      inString = true;
    } else if (char == 123) {
      depth++;
    } else if (char == 125 && --depth == 0) {
      return html.substring(start, i + 1);
    }
  }
  return '';
}

// Quoted attributes may contain literal angle brackets.
int _tagEnd(String source, int start) {
  var quote = 0;
  for (var i = start; i < source.length; i++) {
    final c = source.codeUnitAt(i);
    if (quote != 0) {
      if (c == quote) quote = 0;
    } else if (c == 34 || c == 39) {
      quote = c;
    } else if (c == 62) {
      return i;
    }
  }
  return -1;
}

Map<String, String> _attributes(String source) => {
  for (final match in _attribute.allMatches(source))
    match[1]!.toLowerCase(): _entities(match[2] ?? match[3] ?? match[4] ?? ''),
};

final _entity = RegExp(r'&(#(?:[xX][\da-fA-F]+|\d+)|[\w]+);');
String _entities(String value) => value.contains('&')
    ? value.replaceAllMapped(_entity, (m) {
        final token = m[1]!;
        const named = {
          'amp': '&',
          'quot': '"',
          'apos': "'",
          'lt': '<',
          'gt': '>',
          'nbsp': ' ',
          'frac12': '½',
          'frac14': '¼',
          'frac34': '¾',
          'ndash': '–',
          'mdash': '—',
          'hellip': '…',
          'ldquo': '“',
          'rdquo': '”',
          'lsquo': '‘',
          'rsquo': '’',
          'deg': '°',
        };
        if (!token.startsWith('#')) return named[token] ?? m[0]!;
        final hex = token.startsWith('#x') || token.startsWith('#X');
        final code = int.tryParse(
          token.substring(hex ? 2 : 1),
          radix: hex ? 16 : 10,
        );
        return code != null &&
                code > 0 &&
                code <= 0x10ffff &&
                !(code >= 0xd800 && code <= 0xdfff)
            ? String.fromCharCode(code)
            : m[0]!;
      })
    : value;
