import 'package:flutter/material.dart';

/// A display-only lead-in; punctuation, whitespace and the original text survive.
TextSpan stepSpan(String text) {
  final colon = text.indexOf(':');
  if (colon <= 0) return TextSpan(text: text);
  final phrase = text.substring(0, colon);
  final startsWithLetter = RegExp(r'^\p{L}', unicode: true).hasMatch(phrase);
  if (!startsWithLetter ||
      phrase.contains('.') ||
      phrase.contains('/') ||
      phrase.contains('\n') ||
      phrase.trim().split(RegExp(r'\s+')).length > 5 ||
      RegExp(r'\d:\d').hasMatch(
        text.substring(colon - 1, (colon + 2).clamp(0, text.length)),
      ) ||
      (text.substring(colon + 1).startsWith('//') ||
          RegExp(
            r'^(?:https?|ftp|mailto|tel|file|data):',
            caseSensitive: false,
          ).hasMatch(text))) {
    return TextSpan(text: text);
  }
  return TextSpan(
    children: [
      TextSpan(
        text: text.substring(0, colon + 1),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      TextSpan(text: text.substring(colon + 1)),
    ],
  );
}
