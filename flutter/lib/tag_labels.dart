/// Presentation/input normalization only; stored recipes change on explicit save.
List<String> normalizeTags(Iterable<String> tags) => tags
    .map((tag) => tag.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((tag) => tag.isNotEmpty)
    .toSet()
    .toList();
