import 'package:cookdex/name_matching.dart';
import 'package:flutter_test/flutter_test.dart';

NameObservation observation(String name, String id, [String? date]) =>
    NameObservation(
      name: name,
      recipeId: id,
      updatedAt: date ?? '2026-10-01T00:00:00Z',
    );

void main() {
  test('whitespace cleanup preserves display spelling and punctuation', () {
    expect(normalizeNameWhitespace('  Dijon\t mustard.\n'), 'Dijon mustard.');
    expect(normalizeNameWhitespace('海塩\u00a0\u2003粉'), '海塩 粉');
  });

  test('keys ignore case, stray punctuation and dash/space differences', () {
    for (final name in [' Chili-Powder. ', 'CHILI  POWDER', 'chili–powder']) {
      expect(sameNameKey(name), 'chili powder');
    }
    expect(sameNameKey('“Baker’s” yeast!'), sameNameKey('Bakers yeast'));
    expect(sameNameKey(' ... '), isEmpty);
    expect(sameNameKey('egg'), isNot(sameNameKey('eggs')));
  });

  test('Unicode letters and accents remain meaningful', () {
    expect(sameNameKey('ÉPICES.'), 'épices');
    expect(sameNameKey('海塩。'), '海塩');
    expect(sameNameKey('海塩'), isNot(sameNameKey('砂糖')));
    expect(sameNameKey('café'), isNot(sameNameKey('cafe')));
    expect(sameNameKey('ملح'), 'ملح');
    expect(sameNameKey('काली मिर्च'), 'काली मिर्च');
  });

  test('distinct recipe usage wins over repeated rows and recency', () {
    final result = groupNameSuggestions([
      observation('Dijon mustard', 'a'),
      observation(' Dijon  mustard ', 'b'),
      for (var i = 0; i < 8; i++)
        observation('DIJON MUSTARD.', 'c', '2026-10-15T00:00:00Z'),
    ]).single;
    expect(result.name, 'Dijon mustard');
    expect(result.recipeCount, 3);
    expect(result.latestUpdatedAt, '2026-10-15T00:00:00Z');
  });

  test('tied counts select newest recipe using timestamp instants', () {
    final result = groupNameSuggestions([
      observation('Chili-Powder', 'a', '2026-10-01T01:00:00+02:00'),
      observation('chili powder.', 'b', '2026-10-01T00:00:00Z'),
    ]).single;
    expect(result.name, 'chili powder.');
  });

  test('final spelling ties and group order are deterministic', () {
    final input = [
      observation('egg', 'a'),
      observation('Salt', 'a'),
      observation('salt', 'b'),
      observation('eggs', 'c'),
      observation(' . ', 'd'),
      observation('', 'e'),
    ];
    final forward = groupNameSuggestions(input);
    final reverse = groupNameSuggestions(input.reversed);
    expect(forward.map((s) => s.name), ['Salt', 'egg', 'eggs']);
    expect(reverse.map((s) => s.name), forward.map((s) => s.name));
  });

  test('multiple spellings in one recipe count once in a group', () {
    final result = groupNameSuggestions([
      observation('salt', 'a'),
      observation('Salt.', 'a'),
      observation('salt', 'b'),
    ]).single;
    expect(result.recipeCount, 2);
    expect(result.name, 'salt');
  });

  test('groups rank recipe count before latest use, then key', () {
    final result = groupNameSuggestions([
      observation('salt', 'a'),
      observation('Salt.', 'b'),
      observation('pepper', 'c', '2026-10-02T00:00:00Z'),
      observation('eggs', 'd'),
      observation('egg', 'e'),
    ]);
    expect(result.map((s) => s.key), ['salt', 'pepper', 'egg', 'eggs']);
  });

  test('equivalent timestamp representations remain deterministic', () {
    final input = [
      observation('Salt', 'a', '2026-10-01T01:00:00+01:00'),
      observation('Salt', 'b', '2026-10-01T00:00:00Z'),
    ];
    expect(
      groupNameSuggestions(input).single.latestUpdatedAt,
      groupNameSuggestions(input.reversed).single.latestUpdatedAt,
    );
  });
}
