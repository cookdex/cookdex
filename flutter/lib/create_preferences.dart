enum CreateStep {
  photo('Photo recognition'),
  ideas('Recipe ideas'),
  recipe('Full recipe');

  const CreateStep(this.label);
  final String label;
}

/// Device-local Smart Create defaults, independent of the recipe library.
class CreatePreferences {
  static const modelNames = {
    'gemini-3.5-flash-lite': 'Gemini 3.5 Flash-Lite',
    'gemini-3.8-flash': 'Gemini 3.8 Flash',
    'gemini-3.1-pro-preview': 'Gemini 3.1 Pro preview',
    'gemini-4-argon': 'Gemini 4 Argon',
  };
  static String modelName(String id) => modelNames[id] ?? id;
  static String thinkingName(String value) =>
      '${value[0].toUpperCase()}${value.substring(1)} thinking';
  static const suggestedModel = 'gemini-3.8-flash';
  static const suggestedThinking = 'low';

  const CreatePreferences.defaults()
    : _staples = const [
        'salt',
        'pepper',
        'oil',
        'butter',
        'flour',
        'sugar',
        'basic spices',
      ],
      _avoid = const [],
      otherPreferences = '',
      servings = 4,
      extraIngredients = 4,
      photoModel = suggestedModel,
      ideaModel = suggestedModel,
      recipeModel = suggestedModel,
      photoThinking = suggestedThinking,
      ideaThinking = suggestedThinking,
      recipeThinking = suggestedThinking,
      _retiredModels = const {};

  CreatePreferences._({
    required List<String> staples,
    required List<String> avoid,
    required this.otherPreferences,
    required this.servings,
    required this.extraIngredients,
    required this.photoModel,
    required this.ideaModel,
    required this.recipeModel,
    required this.photoThinking,
    required this.ideaThinking,
    required this.recipeThinking,
    required Map<CreateStep, String> retiredModels,
  }) : _staples = List.unmodifiable(staples),
       _avoid = List.unmodifiable(avoid),
       _retiredModels = Map.unmodifiable(retiredModels);

  final List<String> _staples, _avoid;
  List<String> get staples => _staples;
  List<String> get avoid => _avoid;
  final String otherPreferences;
  final int servings;
  final int extraIngredients;
  final String photoModel, ideaModel, recipeModel;
  final String photoThinking, ideaThinking, recipeThinking;
  final Map<CreateStep, String> _retiredModels;

  String? retiredModelFor(CreateStep step) => _retiredModels[step];

  String modelFor(CreateStep step) => switch (step) {
    CreateStep.photo => photoModel,
    CreateStep.ideas => ideaModel,
    CreateStep.recipe => recipeModel,
  };

  String thinkingFor(CreateStep step) => switch (step) {
    CreateStep.photo => photoThinking,
    CreateStep.ideas => ideaThinking,
    CreateStep.recipe => recipeThinking,
  };

  CreatePreferences withSelection(
    CreateStep step,
    String model,
    String thinking,
  ) => switch (step) {
    CreateStep.photo => copyWith(photoModel: model, photoThinking: thinking),
    CreateStep.ideas => copyWith(ideaModel: model, ideaThinking: thinking),
    CreateStep.recipe => copyWith(recipeModel: model, recipeThinking: thinking),
  };

  CreatePreferences withRetiredModel(CreateStep step, String retiredModel) {
    if (modelFor(step) != retiredModel || retiredModel == suggestedModel) {
      return this;
    }
    return withSelection(
      step,
      suggestedModel,
      suggestedThinking,
    ).copyWith(retiredModels: {..._retiredModels, step: retiredModel});
  }

  static List<String> thinkingLevels(String model) => [
    'default',
    if (!const {
      'gemini-3.1-pro-preview',
      'gemini-3.7-flash',
      'gemini-3.8-flash',
      'gemini-4-argon',
    }.contains(model))
      'minimal',
    'low',
    'medium',
    'high',
  ];

  CreatePreferences copyWith({
    List<String>? staples,
    List<String>? avoid,
    String? otherPreferences,
    int? servings,
    int? extraIngredients,
    String? photoModel,
    String? ideaModel,
    String? recipeModel,
    String? photoThinking,
    String? ideaThinking,
    String? recipeThinking,
    Map<CreateStep, String>? retiredModels,
  }) => CreatePreferences._(
    staples: staples ?? this.staples,
    avoid: avoid ?? this.avoid,
    otherPreferences: otherPreferences?.trim() ?? this.otherPreferences,
    servings: servings ?? this.servings,
    extraIngredients: (extraIngredients ?? this.extraIngredients).clamp(1, 6),
    photoModel: photoModel ?? this.photoModel,
    ideaModel: ideaModel ?? this.ideaModel,
    recipeModel: recipeModel ?? this.recipeModel,
    photoThinking: photoThinking ?? this.photoThinking,
    ideaThinking: ideaThinking ?? this.ideaThinking,
    recipeThinking: recipeThinking ?? this.recipeThinking,
    retiredModels:
        retiredModels ??
        {
          for (final entry in _retiredModels.entries)
            if (switch (entry.key) {
              CreateStep.photo => photoModel == null && photoThinking == null,
              CreateStep.ideas => ideaModel == null && ideaThinking == null,
              CreateStep.recipe =>
                recipeModel == null && recipeThinking == null,
            })
              entry.key: entry.value,
        },
  );

  Map<String, Object> toJson() => {
    'staples': staples,
    'avoid': avoid,
    'otherPreferences': otherPreferences,
    'servings': servings,
    'extraIngredients': extraIngredients,
    'photoModel': photoModel,
    'ideaModel': ideaModel,
    'recipeModel': recipeModel,
    'photoThinking': photoThinking,
    'ideaThinking': ideaThinking,
    'recipeThinking': recipeThinking,
    if (_retiredModels.isNotEmpty)
      'retiredModels': {
        for (final e in _retiredModels.entries) e.key.name: e.value,
      },
  };

  factory CreatePreferences.fromJson(Object? data) {
    const defaults = CreatePreferences.defaults();
    if (data is! Map) return defaults;
    List<String> names(String key, List<String> fallback) {
      final value = data[key];
      if (value is! List) return fallback;
      final seen = <String>{};
      return value
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty && seen.add(s.toLowerCase()))
          .toList();
    }

    String model(String key, String fallback) {
      final value = data[key];
      return value is String && value.trim().isNotEmpty
          ? value.trim()
          : fallback;
    }

    String thinking(String key, String model, String fallback) {
      final levels = thinkingLevels(model);
      final value = data[key];
      return value is String && levels.contains(value)
          ? value
          : levels.contains(fallback)
          ? fallback
          : 'default';
    }

    final photo = model('photoModel', defaults.photoModel);
    final idea = model('ideaModel', defaults.ideaModel);
    final recipe = model('recipeModel', defaults.recipeModel);
    final count = data['servings'];
    final extras = data['extraIngredients'];
    final retired = data['retiredModels'];
    return CreatePreferences._(
      staples: names('staples', defaults.staples),
      avoid: names('avoid', defaults.avoid),
      otherPreferences: data['otherPreferences'] is String
          ? (data['otherPreferences'] as String).trim()
          : defaults.otherPreferences,
      servings: count is int && count >= 1 && count <= 99
          ? count
          : defaults.servings,
      extraIngredients: extras is int && extras >= 1 && extras <= 6
          ? extras
          : defaults.extraIngredients,
      retiredModels: {
        if (retired is Map)
          for (final step in CreateStep.values)
            if (retired[step.name] case final String model
                when model.trim().isNotEmpty)
              step: model.trim(),
      },
      photoModel: photo,
      ideaModel: idea,
      recipeModel: recipe,
      photoThinking: thinking('photoThinking', photo, defaults.photoThinking),
      ideaThinking: thinking('ideaThinking', idea, defaults.ideaThinking),
      recipeThinking: thinking(
        'recipeThinking',
        recipe,
        defaults.recipeThinking,
      ),
    );
  }
}
