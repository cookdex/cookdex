import 'dart:convert';

import 'package:cookdex/social_import_page.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'abc123DEF_-';
final _watch = Uri.https('www.youtube.com', '/watch', {'v': _id});

String _player({
  String title = 'Carrot and almond soup',
  String desc = 'Watch my soup recipe!',
  String id = _id,
  String status = 'OK',
  String reason = '',
  bool private = false,
  bool? unlisted = false,
  String duration = '105',
}) {
  final data = {
    'playabilityStatus': {'status': status, 'reason': reason},
    'videoDetails': {
      'videoId': id,
      'title': title,
      'shortDescription': desc,
      'lengthSeconds': duration,
      'isPrivate': private,
    },
    'microformat': {
      'playerMicroformatRenderer': {'isUnlisted': ?unlisted},
    },
  };
  return '<script>var ytInitialPlayerResponse = ${jsonEncode(data)};</script>';
}

SocialImportPage _parse(String url, String html) {
  final uri = Uri.parse(url);
  return SocialImportPage.parse(socialSite(uri)!, uri, html);
}

void main() {
  test('known sites and share hosts have domain boundaries', () {
    for (final (host, expected) in [
      ('youtu.be', SocialSite.youtube),
      ('m.youtube.com', SocialSite.youtube),
      ('vm.tiktok.com', SocialSite.tiktok),
      ('vt.tiktok.com', SocialSite.tiktok),
      ('www.instagram.com', SocialSite.instagram),
      ('instagr.am', SocialSite.instagram),
      ('www.threads.net', SocialSite.threads),
      ('threads.com', SocialSite.threads),
      ('fb.me', SocialSite.facebook),
      ('m.facebook.com', SocialSite.facebook),
      ('t.co', SocialSite.x),
      ('pin.it', SocialSite.pinterest),
      ('www.pinterest.co.uk', SocialSite.pinterest),
      ('redd.it', SocialSite.reddit),
      ('fb.watch', SocialSite.facebook),
      ('mobile.twitter.com', SocialSite.x),
    ]) {
      expect(socialSite(Uri.https(host, '/')), expected);
    }
    for (final host in [
      'myyoutube.com',
      'pinterest.example',
      'threads.net.example.org',
      'notinstagram.com',
      'youtube.com.example.org',
    ]) {
      expect(socialSite(Uri.https(host, '/')), isNull);
    }
    final wrongHost = SocialImportPage.parse(
      SocialSite.youtube,
      Uri.https('example.org', '/watch', {'v': _id}),
      _player(),
    );
    expect(wrongHost.blocked, isTrue);
  });

  test(
    'watch, Shorts and short links identify only one exact public video',
    () {
      for (final url in [
        _watch.toString(),
        'https://youtu.be/$_id?si=abc',
        'https://www.youtube.com/shorts/$_id?feature=share',
      ]) {
        final page = _parse(
          url,
          _player(desc: 'A caption with nested {braces} and "quotes".'),
        );
        expect(page.videoUrl, _watch);
        expect(page.seconds, 105);
        expect(page.text, contains('{braces}'));
      }
      expect(
        canonicalYouTubeVideo(Uri.parse('${_watch.toString()}&v=otherID1234')),
        isNull,
      );
      expect(
        canonicalYouTubeVideo(
          Uri.parse('https://www.youtube.com/playlist?list=album'),
        ),
        isNull,
      );
      expect(
        _parse(_watch.toString(), _player(id: 'wrongVID123')).blocked,
        isTrue,
      );
    },
  );

  test(
    'short and mobile links may redirect only to the same YouTube video',
    () {
      for (final url in [
        'https://youtu.be/$_id',
        'https://m.youtube.com/watch?v=$_id',
      ]) {
        expect(matchesSocialPostRedirect(Uri.parse(url), _watch), isTrue);
      }
      for (final target in [
        'https://www.youtube.com/watch?v=wrongVID123',
        'https://consent.youtube.com/watch?v=$_id',
        'https://www.instagram.com/reel/$_id/',
        'https://www.youtube.com/channel/a',
      ]) {
        expect(matchesSocialPostRedirect(_watch, Uri.parse(target)), isFalse);
      }
    },
  );

  test(
    'unlisted, private, inaccessible, unknown visibility and unknown length',
    () {
      for (final html in [
        _player(private: true),
        _player(unlisted: true),
        _player(status: 'LOGIN_REQUIRED', reason: 'This video is private'),
      ]) {
        final page = _parse(_watch.toString(), html);
        expect(page.nonPublic, isTrue);
        expect(page.blocked, isTrue);
        expect(page.videoUrl, isNull);
        expect(page.text, isEmpty);
      }
      final unavailable = _parse(_watch.toString(), _player(status: 'ERROR'));
      expect(unavailable.blocked, isTrue);
      expect(unavailable.nonPublic, isFalse);
      for (final html in [
        _player(duration: 'unknown'),
        '<meta name="description" content="A soup recipe">',
      ]) {
        final page = _parse(_watch.toString(), html);
        expect(page.blocked, isFalse);
        expect(page.videoUrl, _watch);
        expect(page.seconds, isNull);
      }
      final uncertain = _parse(
        _watch.toString(),
        _player(unlisted: null, duration: '901'),
      );
      expect(uncertain.unconfirmedVisibility, isTrue);
      expect(uncertain.seconds, 901);
        expect(uncertain.title, isEmpty);
        expect(uncertain.text, isEmpty);
      final refused = _player(status: 'UNPLAYABLE')
          .replaceFirst('</script>', ' otherSetup();</script>');
      expect(_parse(_watch.toString(), refused).videoUrl, isNull);
    },
  );

  test('login, consent, human and script challenge pages expose no post', () {
    for (final (url, wall) in [
      ('https://www.youtube.com/login/', ''),
      ('https://consent.youtube.com/', ''),
      (_watch.toString(), '<title>Before you continue to YouTube</title>'),
      (_watch.toString(), '<main>Please sign in to watch this content.</main>'),
      (_watch.toString(), '<h1>Verify you are human</h1>'),
      (_watch.toString(), '<title>Video unavailable - YouTube</title>'),
      (_watch.toString(), '<form action="/login"><input type=password></form>'),
      (
        _watch.toString(),
        '<form hidden><input name="js_challenge" value="1"></form>',
      ),
    ]) {
      final html = '$wall${_player()}';
      expect(isImportAccessWall(Uri.parse(url), html), isTrue, reason: url);
      final result = _parse(url, html);
      expect(result.blocked, isTrue);
      expect(result.videoUrl, isNull);
      expect(result.text, isEmpty);
    }
    const public =
        '<noscript>Enable JavaScript to continue</noscript>'
        '<header><a href="/login">Log in</a></header><article>Soup</article>';
    expect(isImportAccessWall(_watch, public), isFalse);
  });

  test('blocked hosts expose no written recipe or watch', () {
    for (final site in SocialSite.values.where(
      (s) => s != SocialSite.youtube,
    )) {
      final page = SocialImportPage.parse(site, _watch, _player());
      expect(page.blocked, isTrue);
      expect(page.text, isEmpty);
      expect(page.videoUrl, isNull);
    }
  });
}
