import 'dart:convert';

import 'package:cookdex/gemini_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> providerError(String message, {String status = 'INVALID_ARGUMENT'}) =>
    utf8.encode(
      jsonEncode({
        'error': {'message': message, 'status': status},
      }),
    );

void main() {
  const settings = 'Smart Import settings';

  test(
    'URL context refusal gives page-specific recovery only for web requests',
    () {
      final bytes = providerError(
        'URL context tool is not supported by this model.',
      );
      expect(
        geminiCapabilityMessage(400, bytes, settings: settings, webPage: true),
        'This model cannot open web pages. Choose another model in '
        'Smart Import settings, or paste the recipe text.',
      );
      expect(geminiCapabilityMessage(400, bytes, settings: settings), isNull);
    },
  );

  test(
    'image refusal gives photo-specific recovery only for photo requests',
    () {
      final bytes = providerError('This model does not support image inputs.');
      expect(
        geminiCapabilityMessage(400, bytes, settings: settings, photos: true),
        'This model cannot read photos. Choose a model that supports '
        'images in Smart Import settings.',
      );
      expect(geminiCapabilityMessage(400, bytes, settings: settings), isNull);
    },
  );

  test(
    'thinking refusal names the chosen feature and supplied settings page',
    () {
      expect(
        geminiCapabilityMessage(
          422,
          providerError(
            'Thinking level minimal is not supported for this model.',
          ),
          settings: 'Smart Create settings',
        ),
        'This model does not support the selected thinking level. '
        'Choose another level or model in Smart Create settings.',
      );
    },
  );

  test('structured reply refusal explains the required recipe format', () {
    expect(
      geminiCapabilityMessage(
        400,
        providerError('Structured output response_format is unsupported.'),
        settings: settings,
      ),
      'This model cannot return the structured recipe replies cookdex '
      'needs. Choose another model in Smart Import settings.',
    );
  });

  test('video refusal suggests the written recipe only during watching', () {
    final bytes = providerError('Video input is not available for this model.');
    expect(
      geminiCapabilityMessage(400, bytes, settings: settings, video: true),
      'This model cannot watch the video. Try importing the written '
      'recipe or a recipe page linked in its description.',
    );
    expect(geminiCapabilityMessage(400, bytes, settings: settings), isNull);
  });

  for (final (status, reason, category) in [
    (
      429,
      'URL context is not available because the quota is exhausted.',
      'RESOURCE_EXHAUSTED',
    ),
    (429, 'YouTube video daily quota exhausted', 'RESOURCE_EXHAUSTED'),
    (
      400,
      'API key not valid. Please pass a valid API key.',
      'INVALID_ARGUMENT',
    ),
    (401, 'API key cannot authorize this image request.', 'UNAUTHENTICATED'),
    (
      403,
      'Your API key was reported as leaked. Please use another API key.',
      'PERMISSION_DENIED',
    ),
    (403, 'The caller does not have permission.', 'PERMISSION_DENIED'),
    (404, 'Requested model was not found.', 'NOT_FOUND'),
    (503, 'Service unavailable. Please try again.', 'UNAVAILABLE'),
    (200, 'Thinking is unsupported.', 'OK'),
  ]) {
    test(
      '$status $category is not mislabeled as a model capability refusal',
      () {
        expect(
          geminiCapabilityMessage(
            status,
            providerError(reason, status: category),
            settings: settings,
            webPage: true,
            photos: true,
            video: true,
          ),
          isNull,
        );
      },
    );
  }

  test('missing or malformed error payloads keep the ordinary error path', () {
    for (final value in [
      '',
      '<html>Service failure</html>',
      '[]',
      '{"error":"unsupported"}',
      '{}',
    ]) {
      expect(
        geminiCapabilityMessage(400, utf8.encode(value), settings: settings),
        isNull,
      );
    }
  });
}
