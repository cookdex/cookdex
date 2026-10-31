import 'package:cookdex/release_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release Markdown becomes clean inert text', () {
    expect(
      plainReleaseNotes('''# cookdex 1.9.0

## What's new ##
- **Search** improvements
* __Better__ scrolling
1. Read [the notes](https://example.invalid/a_(b))
2) Open [the release][release]

[release]: https://example.invalid "Release"

> *Enjoy* cooking with `cookdex`.
<b>Plain</b> &amp; safe
'''),
      '''cookdex 1.9.0

What's new
• Search improvements
• Better scrolling
• Read the notes
• Open the release

Enjoy cooking with cookdex.
Plain & safe''',
    );
  });
  test('code text, escaped punctuation and ordinary underscores survive', () {
    expect(
      plainReleaseNotes(
        'Title\n=====\n\n```text\n2 * 3\n```\nsnake_case_name\n\\# literal',
      ),
      'Title\n\n2 * 3\nsnake_case_name\n# literal',
    );
    expect(
      plainReleaseNotes('![Logo](https://example.invalid/image.png) [broken'),
      'Logo [broken',
    );
    expect(plainReleaseNotes(''), '');
  });
  test('large malformed and nested input is bounded without recursive parsing', () {
    final malformed = List.filled(60000, '[').join();
    expect(plainReleaseNotes(malformed), malformed);
    final nested =
        '${List.filled(10000, '[').join()}text${List.filled(10000, ']').join()}';
    expect(plainReleaseNotes(nested), nested);
  });
}
