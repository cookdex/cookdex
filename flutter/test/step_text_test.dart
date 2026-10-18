import 'package:cookdex/ui/step_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('short letter-led phrases are bold, with original text preserved', () {
    for (final text in [
      'Toast farofa: Add 3 tablespoons…',
      'Émulsionner: Mélanger.',
      'One two three four five: Mix',
    ]) {
      final span = stepSpan(text);
      expect(span.toPlainText(), text);
      expect(
        (span.children!.first as TextSpan).style!.fontWeight,
        FontWeight.bold,
      );
    }
  });
  test('long phrases, sentences, clock times and URLs stay plain', () {
    for (final text in [
      'One two three four five six: Mix',
      'Stir. Then: Mix',
      '12:30 start',
      'https://example.com',
      'mailto:recipebook@local.invalid',
      'Mix without a colon',
    ]) {
      expect(stepSpan(text).children, isNull, reason: text);
      expect(stepSpan(text).toPlainText(), text);
    }
  });
}
