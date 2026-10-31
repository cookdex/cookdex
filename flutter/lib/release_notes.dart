/// Converts the Markdown used in release notes to inert display text.
/// No HTML renderer, link recognizers, network lookups or stored data are used.
String plainReleaseNotes(String markdown) {
  final lines = markdown.replaceAll('\r\n', '\n').split('\n');
  final definition = RegExp(r'^\s{0,3}\[([^\[\]]+)\]:\s*\S');
  final references = <String>{
    for (final line in lines)
      if (definition.firstMatch(line) case final match?)
        match[1]!.toLowerCase(),
  };
  final output = <String>[];
  String? fence;
  for (var line in lines) {
    final marker = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
    if (marker != null) {
      if (fence == null) {
        fence = marker[1]![0];
      } else if (marker[1]![0] == fence) {
        fence = null;
      }
      continue;
    }
    if (fence != null) {
      output.add(line);
      continue;
    }
    if (definition.hasMatch(line) ||
        RegExp(r'^\s*(?:={2,}|-{2,}|\*{3,}|_{3,})\s*$').hasMatch(line)) {
      continue;
    }
    line = line
        .replaceFirst(RegExp(r'^\s{0,3}#{1,6}\s+'), '')
        .replaceFirst(RegExp(r'\s+#+\s*$'), '')
        .replaceFirst(RegExp(r'^\s*>\s?'), '')
        .replaceFirstMapped(
          RegExp(r'^(\s*)(?:[-+*]|\d+[.)])\s+'),
          (m) => '${m[1]}• ',
        );
    // Pair delimiters once, so malformed or deeply nested input stays linear.
    final pairs = <int, int>{};
    final brackets = <int>[], parentheses = <int>[];
    for (var i = 0; i < line.length; i++) {
      if (line[i] == r'\') {
        i++;
        continue;
      }
      final c = line[i];
      if (c == '[') brackets.add(i);
      if (c == '(') parentheses.add(i);
      if (c == ']' && brackets.isNotEmpty) pairs[brackets.removeLast()] = i;
      if (c == ')' && parentheses.isNotEmpty) {
        pairs[parentheses.removeLast()] = i;
      }
    }
    final text = StringBuffer();
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '!' && i + 1 < line.length && line[i + 1] == '[') continue;
      final close = line[i] == '[' ? pairs[i] : null;
      if (close != null) {
        final next = close + 1;
        final destination = pairs[next];
        if (next < line.length && destination != null && line[next] == '(') {
          text.write(line.substring(i + 1, close));
          i = destination;
          continue;
        }
        // Reference labels cannot contain nested brackets. Avoid repeatedly
        // copying nested malformed labels when a reference definition exists.
        final nested = references.isEmpty ? i : line.indexOf('[', i + 1);
        if (references.isEmpty || (nested >= 0 && nested < close)) {
          text.write(line[i]);
          continue;
        }
        final label = line.substring(i + 1, close);
        if (next < line.length &&
            destination != null &&
            (line[next] == '(' ||
                (line[next] == '[' &&
                    references.contains(
                      (destination == next + 1
                              ? label
                              : line.substring(next + 1, destination))
                          .toLowerCase(),
                    )))) {
          text.write(label);
          i = destination;
          continue;
        }
        if (references.contains(label.toLowerCase())) {
          text.write(label);
          i = close;
          continue;
        }
      }
      text.write(line[i]);
    }
    line = text
        .toString()
        .replaceAllMapped(RegExp(r'<(https?://[^<>\s]+)>'), (m) => m[1]!)
        .replaceAll(RegExp(r'<[^<>]*>'), '')
        .replaceAllMapped(RegExp(r'(\*\*|__|~~|`)([^\n]+?)\1'), (m) => m[2]!)
        .replaceAllMapped(
          RegExp(r'(?<!\w)(\*|_)([^*_\n]+)\1(?!\w)'),
          (m) => m[2]!,
        )
        .replaceAllMapped(RegExp(r'\\([\\`*_{}\[\]()#+.!>~-])'), (m) => m[1]!)
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    output.add(line.trimRight());
  }
  return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
