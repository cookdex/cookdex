import 'package:cookdex/fraction_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all single-character fractions and mixed numbers are display only', () {
    const fractions = [
      '1/2',
      '1/3',
      '2/3',
      '1/4',
      '3/4',
      '1/5',
      '2/5',
      '3/5',
      '4/5',
      '1/6',
      '5/6',
      '1/7',
      '1/8',
      '3/8',
      '5/8',
      '7/8',
      '1/9',
      '1/10',
    ];
    const glyphs = [
      '½',
      '⅓',
      '⅔',
      '¼',
      '¾',
      '⅕',
      '⅖',
      '⅗',
      '⅘',
      '⅙',
      '⅚',
      '⅐',
      '⅛',
      '⅜',
      '⅝',
      '⅞',
      '⅑',
      '⅒',
    ];
    for (var i = 0; i < fractions.length; i++) {
      expect(displayFractions('${fractions[i]} cup'), '${glyphs[i]} cup');
      expect(displayFractions('2 ${fractions[i]} cups'), '2${glyphs[i]} cups');
      expect(
        spokenFractions('2 ${fractions[i]} cups'),
        '2 and ${fractions[i]} cups',
      );
    }
    expect(displayFractions('1/4–1 1/2 cups'), '¼–1½ cups');
    expect(spokenFractions('1/4–1 1/2 cups'), '1/4 to 1 and 1/2 cups');
    expect(displayFractions('3/16–2 3/16 tsp'), '3/16–2 3/16 tsp');
    expect(spokenFractions('3/16–2 3/16 tsp'), '3/16 to 2 and 3/16 tsp');
    for (final plain in [
      '21/40',
      '13/16',
      '0.25',
      'to taste',
      '',
      '2 (14 oz) cans',
    ]) {
      expect(displayFractions(plain), plain);
    }
    expect(displayFractions('1/2/3'), '1/2/3');
    expect(displayFractions('code1/4'), 'code1/4');
  });
}
