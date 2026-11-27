import 'dart:convert';

/// Translate a provider capability refusal without exposing its raw payload.
/// Unknown models remain usable; the provider decides their capabilities.
String? geminiCapabilityMessage(
  int status,
  List<int> bytes, {
  required String settings,
  bool photos = false,
  bool webPage = false,
  bool video = false,
}) {
  if (status >= 200 && status < 300) return null;
  if (!const {400, 403, 404, 422}.contains(status)) return null;
  String reason;
  try {
    final value = jsonDecode(
      utf8.decode(bytes.take(32768).toList(), allowMalformed: true),
    );
    if (value is! Map || value['error'] is! Map) return null;
    reason = '${value['error']['message'] ?? ''}'.toLowerCase();
  } on FormatException {
    return null;
  }
  if (!RegExp(
    r'not support|unsupported|does not have|not available|not enabled|only support|cannot|can not',
  ).hasMatch(reason)) {
    return null;
  }
  if (reason.contains('thinking')) {
    return 'This model does not support the selected thinking level. '
        'Choose another level or model in $settings.';
  }
  if (webPage && RegExp(r'url.?context|web|tool').hasMatch(reason)) {
    return 'This model cannot open web pages. Choose another model in '
        '$settings, or paste the recipe text.';
  }
  if (photos && RegExp(r'image|photo|vision|multimodal').hasMatch(reason)) {
    return 'This model cannot read photos. Choose a model that supports '
        'images in $settings.';
  }
  if (video && reason.contains('video')) {
    return 'This model cannot watch the video. Try importing the written '
        'recipe or a recipe page linked in its description.';
  }
  if (RegExp(r'json|schema|structured|response.format').hasMatch(reason)) {
    return 'This model cannot return the structured recipe replies cookdex '
        'needs. Choose another model in $settings.';
  }
  return null;
}
