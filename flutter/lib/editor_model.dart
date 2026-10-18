import 'src/rust/api.dart' as core;

int _nextEditorId = 0;
String editorId() =>
    'e${DateTime.now().microsecondsSinceEpoch}-${_nextEditorId++}';

/// Raw form text is deliberately separate from canonical recipe quantities.
class EditableIngredient {
  EditableIngredient({
    String? id,
    this.amount = '',
    this.unit = '',
    this.name = '',
    this.prepNote = '',
    this.optional = false,
    this.originalAmount,
    this.originalText,
    this.originalUnit,
    this.originalName,
    this.showNote = false,
  }) : id = id ?? editorId();
  final String id;
  String amount, unit, name, prepNote;
  bool optional, showNote;
  final core.Amount? originalAmount;
  final String? originalText;
  final String? originalUnit;
  final String? originalName;
  String? get amountInput =>
      originalAmount != null && amount == originalText ? null : amount;
  bool get blank =>
      amount.trim().isEmpty &&
      unit.trim().isEmpty &&
      name.trim().isEmpty &&
      prepNote.trim().isEmpty &&
      !optional;
  core.Ingredient canonical(String section) => core.Ingredient(
    amount: originalAmount ?? const core.Amount.unspecified(),
    unit: unit,
    name: name,
    prepNote: prepNote,
    optional: optional,
    section: section,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'unit': unit,
    'name': name,
    'prepNote': prepNote,
    'optional': optional,
    'originalAmount': originalAmount == null
        ? null
        : amountToJson(originalAmount!),
    'originalText': originalText,
    'originalUnit': originalUnit,
    'originalName': originalName,
    'showNote': showNote,
  };
  factory EditableIngredient.fromJson(Map<String, dynamic> j) =>
      EditableIngredient(
        id: j['id'] as String,
        amount: j['amount'] as String,
        unit: j['unit'] as String,
        name: j['name'] as String,
        prepNote: j['prepNote'] as String,
        optional: j['optional'] as bool,
        showNote: j['showNote'] == true,
        originalText: j['originalText'] as String?,
        originalName: j['originalName'] as String?,
        originalUnit:
            j['originalUnit'] as String? ??
            (j['originalAmount'] != null ? j['unit'] as String : null),
        originalAmount: j['originalAmount'] == null
            ? null
            : amountFromJson(j['originalAmount'] as Map<String, dynamic>),
      );
}

class EditableSection {
  EditableSection({String? id, this.name = '', List<EditableIngredient>? rows})
    : id = id ?? editorId(),
      rows = rows ?? [];
  final String id;
  String name;
  final List<EditableIngredient> rows;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'rows': rows.map((r) => r.toJson()).toList(),
  };
  factory EditableSection.fromJson(Map<String, dynamic> j) => EditableSection(
    id: j['id'] as String,
    name: j['name'] as String,
    rows: (j['rows'] as List)
        .map((r) => EditableIngredient.fromJson(r as Map<String, dynamic>))
        .toList(),
  );
}

class EditableStep {
  EditableStep(this.text, {String? id, this.aiGuess = false})
    : id = id ?? editorId();
  final String id;
  String text;
  bool aiGuess;
  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'aiGuess': aiGuess};
}

class EditorDraft {
  EditorDraft({
    this.base,
    this.title = '',
    this.description = '',
    this.servings = '',
    this.prepTime = '',
    this.cookTime = '',
    this.totalTime = '',
    this.source = '',
    this.notes = '',
    List<String>? tags,
    List<EditableSection>? sections,
    List<EditableStep>? steps,
    this.tagInput = '',
    this.error,
    this.pasteText = '',
    this.pasteSectionId,
    this.pasteKind,
    this.stale = false,
    this.imported = false,
    this.exactTextImport = false,
    List<String>? importWarnings,
    Set<String>? aiGuessedFields,
  }) : aiGuessedFields = Set.of(aiGuessedFields ?? {}),
       importWarnings = List.of(importWarnings ?? []),
       tags = List.of(tags ?? []),
       sections =
           sections ??
           [
             EditableSection(rows: [EditableIngredient()]),
           ],
       steps = steps ?? [EditableStep('')];
  bool exactTextImport;
  core.Recipe? base;
  String title,
      description,
      servings,
      prepTime,
      cookTime,
      totalTime,
      source,
      notes,
      tagInput;
  final List<String> tags;
  final List<EditableSection> sections;
  final List<EditableStep> steps;
  String? error, pasteKind, pasteSectionId;
  String pasteText;
  bool stale;
  bool imported;
  final List<String> importWarnings;
  final Set<String> aiGuessedFields;
  bool get unappliedPaste => pasteKind != null && pasteText.trim().isNotEmpty;
  Iterable<(EditableSection, EditableIngredient)> get ingredients sync* {
    for (final section in sections) {
      for (final row in section.rows) {
        if (!row.blank) yield (section, row);
      }
    }
  }

  core.RecipeFields fields() => core.RecipeFields(
    title: title,
    description: description,
    servings: servings,
    prepTime: prepTime,
    cookTime: cookTime,
    totalTime: totalTime,
    source: source,
    tags: tags,
    notes: notes,
    ingredients: ingredients.map((r) => r.$2.canonical(r.$1.name)).toList(),
    steps: steps.map((s) => s.text).toList(),
  );
  List<String?> amountInputs() =>
      ingredients.map((r) => r.$2.amountInput).toList();
  Map<String, dynamic> toJson() => {
    'version': 1,
    'base': base == null ? null : recipeToJson(base!),
    'title': title,
    'description': description,
    'servings': servings,
    'prepTime': prepTime,
    'cookTime': cookTime,
    'totalTime': totalTime,
    'source': source,
    'notes': notes,
    'tags': tags,
    'tagInput': tagInput,
    'sections': sections.map((s) => s.toJson()).toList(),
    'steps': steps.map((s) => s.toJson()).toList(),
    'error': error,
    'pasteText': pasteText,
    'pasteSectionId': pasteSectionId,
    'pasteKind': pasteKind,
    'stale': stale,
    'imported': imported,
    'exactTextImport': exactTextImport,
    'importWarnings': importWarnings,
    'aiGuessedFields': aiGuessedFields.toList(),
  };
  factory EditorDraft.fromJson(Map<String, dynamic> j) {
    if (j['version'] != 1) {
      throw const FormatException('Unsupported editor draft.');
    }
    return EditorDraft(
      base: j['base'] == null
          ? null
          : recipeFromJson(j['base'] as Map<String, dynamic>),
      title: j['title'] as String,
      description: j['description'] as String,
      servings: j['servings'] as String,
      prepTime: j['prepTime'] as String,
      cookTime: j['cookTime'] as String,
      totalTime: j['totalTime'] as String,
      source: j['source'] as String,
      notes: j['notes'] as String,
      tags: (j['tags'] as List).cast<String>().toList(),
      tagInput: j['tagInput'] as String,
      sections: (j['sections'] as List)
          .map((s) => EditableSection.fromJson(s as Map<String, dynamic>))
          .toList(),
      steps: (j['steps'] as List)
          .map(
            (s) => EditableStep(
              s['text'] as String,
              id: s['id'] as String,
              aiGuess: s['aiGuess'] == true,
            ),
          )
          .toList(),
      error: j['error'] as String?,
      pasteKind: j['pasteKind'] as String?,
      pasteSectionId: j['pasteSectionId'] as String?,
      pasteText: j['pasteText'] as String,
      stale: j['stale'] == true,
      imported: j['imported'] == true,
      exactTextImport: j['exactTextImport'] == true,
      importWarnings: (j['importWarnings'] as List? ?? []).cast<String>(),
      aiGuessedFields: (j['aiGuessedFields'] as List? ?? [])
          .cast<String>()
          .toSet(),
    );
  }
  factory EditorDraft.fromRecipe(core.Recipe recipe, List<String> amounts) {
    final f = recipe.fields;
    final sections = <EditableSection>[];
    for (var i = 0; i < f.ingredients.length; i++) {
      final ingredient = f.ingredients[i];
      if (sections.isEmpty || sections.last.name != ingredient.section) {
        sections.add(EditableSection(name: ingredient.section));
      }
      sections.last.rows.add(
        EditableIngredient(
          amount: amounts[i],
          unit: ingredient.unit,
          name: ingredient.name,
          prepNote: ingredient.prepNote,
          optional: ingredient.optional,
          originalAmount: ingredient.amount,
          originalText: amounts[i],
          originalUnit: ingredient.unit,
          originalName: ingredient.name,
          showNote: ingredient.prepNote.isNotEmpty,
        ),
      );
    }
    return EditorDraft(
      base: recipe,
      title: f.title,
      description: f.description,
      servings: f.servings,
      prepTime: f.prepTime,
      cookTime: f.cookTime,
      totalTime: f.totalTime,
      source: f.source,
      notes: f.notes,
      tags: List.of(f.tags),
      sections: sections.isEmpty ? null : sections,
      steps: f.steps.isEmpty ? null : f.steps.map(EditableStep.new).toList(),
    );
  }
}

Map<String, dynamic> amountToJson(core.Amount a) => switch (a) {
  core.Amount_Rational(:final numerator, :final denominator) => {
    'kind': 'rational',
    'numerator': numerator,
    'denominator': denominator,
  },
  core.Amount_Range(
    :final lowerNumerator,
    :final lowerDenominator,
    :final upperNumerator,
    :final upperDenominator,
  ) =>
    {
      'kind': 'range',
      'lowerNumerator': lowerNumerator,
      'lowerDenominator': lowerDenominator,
      'upperNumerator': upperNumerator,
      'upperDenominator': upperDenominator,
    },
  core.Amount_ToTaste() => {'kind': 'toTaste'},
  core.Amount_Unspecified() => {'kind': 'unspecified'},
};
core.Amount amountFromJson(Map<String, dynamic> j) => switch (j['kind']) {
  'rational' => core.Amount.rational(
    numerator: j['numerator'] as int,
    denominator: j['denominator'] as int,
  ),
  'toTaste' => const core.Amount.toTaste(),
  'range' => core.Amount.range(
    lowerNumerator: j['lowerNumerator'] as int,
    lowerDenominator: j['lowerDenominator'] as int,
    upperNumerator: j['upperNumerator'] as int,
    upperDenominator: j['upperDenominator'] as int,
  ),
  'unspecified' => const core.Amount.unspecified(),
  _ => throw const FormatException('Invalid draft quantity.'),
};
Map<String, dynamic> recipeToJson(core.Recipe r) => {
  'id': r.id,
  'favorite': r.favorite,
  'createdAt': r.createdAt,
  'updatedAt': r.updatedAt,
  'revision': r.revision,
  'fields': {
    'title': r.fields.title,
    'description': r.fields.description,
    'servings': r.fields.servings,
    'prepTime': r.fields.prepTime,
    'cookTime': r.fields.cookTime,
    'totalTime': r.fields.totalTime,
    'source': r.fields.source,
    'tags': r.fields.tags,
    'notes': r.fields.notes,
    'steps': r.fields.steps,
    'ingredients': r.fields.ingredients
        .map(
          (i) => {
            'amount': amountToJson(i.amount),
            'unit': i.unit,
            'name': i.name,
            'prepNote': i.prepNote,
            'optional': i.optional,
            'section': i.section,
          },
        )
        .toList(),
  },
};
core.Recipe recipeFromJson(Map<String, dynamic> j) {
  final f = j['fields'] as Map<String, dynamic>;
  return core.Recipe(
    id: j['id'] as String,
    favorite: j['favorite'] as bool,
    createdAt: j['createdAt'] as String,
    updatedAt: j['updatedAt'] as String,
    revision: j['revision'] as int,
    fields: core.RecipeFields(
      title: f['title'] as String,
      description: f['description'] as String,
      servings: f['servings'] as String,
      prepTime: f['prepTime'] as String,
      cookTime: f['cookTime'] as String,
      totalTime: f['totalTime'] as String,
      source: f['source'] as String,
      tags: (f['tags'] as List).cast<String>(),
      notes: f['notes'] as String,
      steps: (f['steps'] as List).cast<String>(),
      ingredients: (f['ingredients'] as List)
          .map(
            (i) => core.Ingredient(
              amount: amountFromJson(i['amount'] as Map<String, dynamic>),
              unit: i['unit'] as String,
              name: i['name'] as String,
              prepNote: i['prepNote'] as String,
              optional: i['optional'] as bool,
              section: i['section'] as String,
            ),
          )
          .toList(),
    ),
  );
}

/// Splits numbered/bulleted lines, blank-line paragraphs, or plain lines.
List<String> splitPastedSteps(String text) {
  final normalized = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .trim();
  if (normalized.isEmpty) return [];
  final marker = RegExp(r'^\s*(?:\d+[.)]|[-*•])\s+', multiLine: true);
  if (marker.hasMatch(normalized)) {
    final pieces = normalized.split(RegExp(r'\n(?=\s*(?:\d+[.)]|[-*•])\s+)'));
    return pieces
        .map((s) => s.replaceFirst(marker, '').trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  final separator = normalized.contains(RegExp(r'\n\s*\n'))
      ? RegExp(r'\n\s*\n')
      : RegExp(r'\n');
  return normalized
      .split(separator)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}
