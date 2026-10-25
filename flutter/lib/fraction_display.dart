import 'package:flutter/painting.dart';

// Bundled coverage keeps every fraction on the same baseline on all platforms.
const amountDisplayStyle = TextStyle(
  fontFamily: 'CookdexAmounts',
  fontWeight: FontWeight.w500,
);

/// Presentation only. Canonical amounts and all editable/exported text stay ASCII.
const _glyphs = {
  '1/2': '½',
  '1/3': '⅓',
  '2/3': '⅔',
  '1/4': '¼',
  '3/4': '¾',
  '1/5': '⅕',
  '2/5': '⅖',
  '3/5': '⅗',
  '4/5': '⅘',
  '1/6': '⅙',
  '5/6': '⅚',
  '1/7': '⅐',
  '1/8': '⅛',
  '3/8': '⅜',
  '5/8': '⅝',
  '7/8': '⅞',
  '1/9': '⅑',
  '1/10': '⅒',
};

final _fraction = RegExp(r'(?<![\w/.])(?:(\d+)\s+)?(\d+/\d+)(?![\w/])');

String displayFractions(String plain) => plain.replaceAllMapped(_fraction, (m) {
  final glyph = _glyphs[m[2]];
  return glyph == null ? m[0]! : '${m[1] ?? ''}$glyph';
});

/// Explicit mixed-number/range wording avoids a reader treating 1¼ as 14.
String spokenFractions(String plain) => plain
    .replaceAllMapped(
      _fraction,
      (m) => m[1] == null ? m[2]! : '${m[1]} and ${m[2]}',
    )
    .replaceAll('–', ' to ');
