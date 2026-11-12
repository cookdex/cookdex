import 'package:cookdex/smart_create_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Json ideaRow(
  String title, {
  List<String> have = const ['i1'],
  List<String> pantry = const [],
  List<String> missing = const [],
  String meal = 'Dinner',
  String effort = 'Easy',
  int minutes = 15,
}) => {
  'title': title,
  'pitch':
      'Cook everything in one skillet until the edges brown. Serve while warm.',
  'ingredients': have,
  'staples': pantry,
  'missing': missing,
  'minutes': minutes,
  'effort': effort,
  'effortNote': 'One skillet and a short simmer.',
  'meal': meal,
};

Json ingredient(String name, String amount, [String unit = '']) => {
  'name': name,
  'amount': amount,
  'unit': unit,
  'section': '',
  'prepNote': '',
  'optional': false,
};

final kitchenD = CreateKitchen(
  ingredients: const [
    'half a rotisserie chicken',
    'a bag of spinach',
    'half a block of cream cheese',
    '4 flour tortillas',
    'a lemon',
  ],
  staples: const ['oil', 'salt'],
);

final wraps = CreateIdea(
  title: 'Lemon chicken and spinach wraps',
  pitch: 'Warm tortillas around a creamy chicken filling. A squeeze of lemon lifts the greens.',
  effort: 'Easy',
  minutes: 18,
  effortNote: 'Wilt the greens, then warm the filled wraps.',
  meal: 'Lunch',
  have: kitchenD.ingredients,
  staples: const ['oil'],
  missing: const [],
);

Json recipeD() => {
  'status': 'ok',
  'reason': '',
  'title': wraps.title,
  'description': wraps.pitch,
  'servings': '4',
  'prepTime': '6 min',
  'cookTime': '12 min',
  'totalTime': '18 min',
  'source': '',
  'notes': 'Refrigerate the filling separately from the tortillas.',
  'tags': ['Lunch'],
  'aiGuessedFields': [],
  'aiGuessedSteps': [],
  'ingredients': [
    ingredient('rotisserie chicken', '1/4'),
    ingredient('rotisserie chicken', '1/4'),
    ingredient('spinach', '1', 'bag'),
    ingredient('cream cheese', '1/2', 'block'),
    ingredient('flour tortillas', '4'),
    ingredient('lemon', '1'),
    ingredient('oil', '1', 'tsp'),
  ],
  'steps': [
    'Wilt spinach: Heat the oil and stir in the spinach until tender.',
    'Warm filling: Fold in both portions of chicken and cream cheese. Heat to 165°F and squeeze in the lemon.',
    'Fill wraps: Divide the filling among the four tortillas. Fold the sides over the filling and serve warm.',
  ],
};

void main() {
  test('descriptions keep the dish and mood while applying preferences silently', () {
    final kitchen = CreateKitchen(
      ingredients: kitchenD.ingredients,
      staples: kitchenD.staples,
      avoid: ['peanuts'],
      otherPreferences: 'avoid egg-heavy dishes',
      mood: 'A cozy lunch',
    );
    const dish = 'The warm filling makes a cozy lunch.';
    List<CreateIdea> ideas(String pitch) => validateIdeas(
      {'ideas': [{...ideaRow(wraps.title), 'pitch': pitch}]}, kitchen, [], [],
    );
    for (final sentence in [
      'It is not egg-heavy.',
      'This recipe avoids egg-heavy dishes.',
      'This fits your dietary preferences.',
    ]) {
      expect(ideas('$dish $sentence').single.pitch, dish);
      expect(validateRecipe(
        {...recipeD(), 'description': '$dish $sentence'}, kitchen, wraps,
      )['description'], dish);
    }
    const eggs = 'A little egg binds the filling.';
    expect(ideas('$dish $eggs').single.pitch, '$dish $eggs');
    expect(ideas('$dish It is free of peanuts.'), isEmpty);
    expect(() => validateRecipe(
      {...recipeD(), 'description': '$dish It is free of peanuts.'}, kitchen, wraps,
    ), throwsA(isA<AvoidedRecipe>()));
  });

  test(
    'idea-only metadata is optional, bounded and limited to known chips',
    () {
      final kitchen = CreateKitchen(
        ingredients: ['rice'],
        staples: [],
        avoid: ['peanuts'],
        mood: 'Around 650 calories',
        otherPreferences: 'Prefer greens',
      );
      CreateIdea read(Json extra) => validateIdeas(
        {
          'ideas': [
            {...ideaRow('Rice bowl'), ...extra},
          ],
        },
        kitchen,
        [],
        [],
      ).single;
      final decorated = read({
        'caloriesPerServing': 650,
        'dietaryChips': [
          'High fiber',
          'Low sugar',
          'Vegetarian',
          'High fiber',
          5,
        ],
      }).withMinutes(25);
      expect(decorated.caloriesPerServing, 650);
      expect(decorated.dietaryChips, ['Vegetarian', 'High fiber']);
      for (final value in [null, '650 cal', -1, 0, 1, 24, 650.3, 2501, 90000]) {
        expect(read({'caloriesPerServing': value}).caloriesPerServing, isNull);
      }
      expect(read({'dietaryChips': 'Vegan'}).dietaryChips, isEmpty);
      expect(kitchen.recipeRequestInput(decorated), {
        'idea': decorated.recipeInput,
        'servings': 4,
        'avoid': ['peanuts'],
        'mood': 'Around 650 calories',
        'otherPreferences': 'Prefer greens',
      });
      expect(decorated.recipeInput.containsKey('caloriesPerServing'), isFalse);
      expect(decorated.recipeInput.containsKey('dietaryChips'), isFalse);
    },
  );

  test('a recipe response repeating calorie estimates or badges loses that metadata', () {
    final written = validateRecipe(
      {
        ...recipeD(),
        'description': '${wraps.pitch} About 650 calories per serving.',
        'steps': [
          'Serve: Divide between four bowls (~480 kcal per serving). Garnish: Scatter the parsley.',
        ],
        'tags': [
          'Lunch',
          'High-protein',
          '~650 cal',
          '~480 kcal/serving',
          'High fiber',
        ],
        'notes': 'Store for two days.\nDietary labels: High protein, High fiber (estimated).\nCalories per serving (estimated): 650.',
        'caloriesPerServing': 650,
        'dietaryChips': ['High protein'],
      },
      kitchenD,
      wraps,
    );
    expect(written['description'], wraps.pitch);
    expect(written['steps'], [
      'Serve: Divide between four bowls. Garnish: Scatter the parsley.',
    ]);
    expect(written['tags'], ['Lunch']);
    expect(written['notes'], 'Store for two days.\n\n$createCredit');
    expect(written.keys, isNot(contains('caloriesPerServing')));
    expect(written.keys, isNot(contains('dietaryChips')));
  });

  test('typed lists preserve first wording and amount across accents, forms and aliases', () {
    expect(
      splitTyped(
        '2 cans of chickpeas, garbanzo beans\nScallions, spring onion, 2 JALAPEÑOS, jalapeno, cherry tomatoes, cherry tomato',
      ),
      ['2 cans of chickpeas', 'Scallions', '2 JALAPEÑOS', 'cherry tomatoes'],
    );
    expect(sameFood('capsicum', 'bell peppers'), isTrue);
    expect(sameFood('bell pepper', 'black pepper'), isFalse);
    expect(sameFood('rice', 'brown rice'), isTrue);
    expect(sameFood('potatoes', 'baby potatoes'), isTrue);
    for (final foods in [
      ('rice', 'cauliflower rice'),
      ('potato', 'sweet potato'),
      ('egg', 'eggplant'),
      ('chickpeas', 'green beans'),
      ('onions', 'onion powder'),
      ('oil', 'olive'),
    ]) {
      expect(sameFood(foods.$1, foods.$2), isFalse, reason: foods.toString());
    }
  });

  test('photo output removes typed, staple and cross-list duplicates while retaining maybe order', () {
    final results = validatePhotos(
      {
        'found': [
          'scallions',
          'garbanzo beans',
          'fresh dill',
          'tomatoes',
          'tomato',
          'cumin',
        ],
        'maybe': [
          'tomato',
          'scallion',
          'country ham',
          'broccoli',
          'kale',
          'leeks',
          'peas',
          'carrots',
          'beans',
          'parsley',
          'celery',
        ],
      },
      ['a bunch of green onions', '2 cans of chickpeas'],
      ['basic spices'],
    );
    expect(results.found, ['fresh dill', 'tomatoes']);
    expect(results.maybe, [
      'country ham',
      'broccoli',
      'kale',
      'leeks',
      'peas',
      'carrots',
      'beans',
      'parsley',
    ]);
  });

  test('idea IDs are scoped, unknown IDs ignored and available missing foods reclassified', () {
    final k = CreateKitchen(
      ingredients: ['2 cans of chickpeas', 'rice'],
      staples: ['salt', 'basic spices'],
      useFirst: {'2 cans of chickpeas'},
    );
    expect(k.input['useFirst'], ['i1']);
    final checks = <String>[];
    final result = validateIdeas(
      {
        'ideas': [
          ideaRow(
            'Spiced chickpeas',
            have: ['s1', 'i10', 'i2', 'i2'],
            pantry: ['i2', 's1'],
            missing: ['garbanzo beans', 'cumin', 'lemon', 'lemons'],
          ),
          ideaRow('All unknown', have: ['i10'], pantry: ['s1']),
          ideaRow(
            'Too many missing',
            missing: ['lentils', 'carrots', 'celery', 'leeks', 'lime'],
          ),
          ideaRow('No use-first item', have: ['i2']),
        ],
      },
      k,
      [],
      checks,
    );
    expect(result.single.title, 'Spiced chickpeas');
    expect(result.single.have, ['rice', '2 cans of chickpeas']);
    expect(result.single.staples, ['salt', 'basic spices']);
    expect(result.single.missing, ['lemon']);
    expect(checks.join(' '), contains('i10'));
    expect(
      validateIdeas(
        {
          'ideas': [
            ideaRow('Plain rice', have: ['i2']),
          ],
        },
        CreateKitchen(ingredients: k.ingredients, staples: k.staples),
        [],
        [],
      ).single.have,
      ['rice'],
    );
  });

  test(
    'discovery caps count only foods beyond the kitchen and its staples',
    () {
      final foods = ['carrots', 'noodles', 'lime', 'ginger', 'celery', 'leeks'];
      for (var cap = 1; cap <= 6; cap++) {
        final k = CreateKitchen(
          ingredients: ['rice'],
          staples: ['oil'],
          extraIngredients: cap,
        );
        final rows = [
          ideaRow('Rice bowl', missing: ['rice', 'oil', ...foods.take(cap)]),
          ideaRow('Long list', missing: [...foods.take(cap), 'cabbage']),
        ];
        expect(
          validateIdeas({'ideas': rows}, k, [], []).single.missing,
          foods.take(cap),
        );
      }
      final mood = CreateKitchen(
        ingredients: [],
        staples: ['oil'],
        mood: 'soup',
        avoid: ['peanuts'],
        extraIngredients: 1,
      );
      final shopping = [...foods, 'cabbage', 'miso', 'broth', 'peas'];
      final accepted = validateIdeas(
        {
          'ideas': [
            ideaRow('Brothy noodles', have: [], missing: ['oil', ...shopping]),
            ideaRow('Long list', have: [], missing: [...shopping, 'coconut']),
            ideaRow('Peanut soup', have: [], missing: ['peanuts']),
            ideaRow('No ingredients', have: []),
            ideaRow('Staples only', have: [], pantry: ['s1']),
          ],
        },
        mood,
        [],
        [],
      );
      expect(accepted.map((idea) => idea.title), [
        'Staples only',
        'Brothy noodles',
      ]);
      expect(accepted.last.missing, shopping);
      expect(accepted.last.staples, ['oil']);
    },
  );

  test('time bands use 20 and 40 minute boundaries, meal and effort filters use actual duration', () {
    final k = CreateKitchen(ingredients: ['eggs'], staples: []);
    final rows = [
      for (final minutes in [19, 20, 40, 41])
        ideaRow('Egg skillet $minutes', minutes: minutes),
    ];
    final results = validateIdeas({'ideas': rows}, k, [], []);
    expect(results.map((i) => i.effort), [
      'Easy',
      'Medium',
      'Medium',
      'Involved',
    ]);
    final filtered = validateIdeas(
      {
        'ideas': [...rows, ideaRow('Lunch eggs', meal: 'Lunch', minutes: 27)],
      },
      CreateKitchen(
        ingredients: ['eggs'],
        staples: [],
        meal: 'Dinner',
        effort: 'Medium',
      ),
      [],
      [],
    );
    expect(filtered.map((i) => i.minutes), [20, 40]);
  });

  test(
    'rank entire batch by missing, use-first and owned counts, preserving ties',
    () {
      final k = CreateKitchen(
        ingredients: ['eggs', 'rice', 'scallions'],
        staples: [],
        useFirst: {'eggs', 'rice'},
      );
      final result = validateIdeas(
        {
          'ideas': [
            ideaRow('Missing lime', missing: ['lime']),
            ideaRow('Plain eggs'),
            ideaRow('Eggs with greens', have: ['i1', 'i3']),
            ideaRow('Rice and eggs', have: ['i1', 'i2']),
            ideaRow('Another pair', have: ['i2', 'i1']),
            ideaRow('All three', have: ['i1', 'i2', 'i3']),
          ],
        },
        k,
        [],
        [],
        limit: 4,
      );
      expect(result.map((i) => i.title), [
        'All three',
        'Rice and eggs',
        'Another pair',
        'Eggs with greens',
      ]);
    },
  );

  test('earlier titles and duplicates within a batch fold accents, punctuation and plural forms', () {
    final result = validateIdeas(
      {
        'ideas': [
          ideaRow('Lémon eggs!'),
          ideaRow('Herb egg'),
          ideaRow('Herb Eggs'),
          ideaRow('Quick scramble'),
        ],
      },
      CreateKitchen(ingredients: ['eggs'], staples: []),
      ['Lemon Egg'],
      [],
    );
    expect(result.map((i) => i.title), ['Herb egg', 'Quick scramble']);
  });

  test(
    'composite foods in idea ingredients or optional prose honor exclusions',
    () {
      final k = CreateKitchen(
        ingredients: ['chicken'],
        staples: [],
        avoid: ['nuts', 'wheat'],
      );
      final results = validateIdeas(
        {
          'ideas': [
            ideaRow('Warm chicken', missing: ['basil pesto']),
            ideaRow('Chicken skillet')
              ..['pitch'] = 'Add a drizzle of teriyaki at the table.',
            ideaRow('Chicken rolls')
              ..['effortNote'] = 'Finish with soy sauce if desired.',
            ideaRow('Pan chicken'),
          ],
        },
        k,
        [],
        [],
      );
      expect(results.map((i) => i.title), ['Pan chicken']);
      expect(containsAvoided('pesto', ['pine nuts']), isTrue);
      expect(
        containsAvoided('Fold in the diced peppers.', ['peppers']),
        isTrue,
      );
      expect(containsAvoided('peppers', ['peppers']), isTrue);
      expect(containsAvoided('green peas', ['peanuts']), isFalse);
    },
  );

  test('kitchen D accepts exactly the whole batch and writes the Notes credit once', () {
    final dish = recipeD()
      ..['notes'] = 'Cool the filling before storing.\n$createCredit';
    final checked = validateRecipe(dish, kitchenD, wraps);
    expect(checked['source'], '');
    expect(
      checked['notes'],
      'Cool the filling before storing.\n\n$createCredit',
    );
    expect(checked['ingredients'], dish['ingredients']);
  });

  test('stock quantities are enforced across lines and package units, including optional quantities', () {
    for (final edit in [
      (Json j) => (j['ingredients'][1] as Json)['amount'] = '1/2',
      (Json j) => (j['ingredients'][2] as Json)['unit'] = 'oz',
      (Json j) => (j['ingredients'][3] as Json)['amount'] = '1',
      (Json j) => (j['ingredients'][4] as Json)['amount'] = '5',
      (Json j) => (j['ingredients'][5] as Json)['amount'] = '2',
      (Json j) => (j['ingredients'] as List).add(
        ingredient('lemon', '1')..['optional'] = true,
      ),
      (Json j) =>
          j['steps'] = ['Warm: Heat twelve tortillas in a dry skillet.'],
      (Json j) => j['notes'] = 'Stir in two blocks of cream cheese.',
      for (final amount in ['NaN', '-1', '0', '1/0', 'Infinity'])
        (Json j) => (j['ingredients'][1] as Json)['amount'] = amount,
    ]) {
      final j = recipeD();
      edit(j);
      expect(
        () => validateRecipe(j, kitchenD, wraps),
        throwsFormatException,
        reason: '${j['ingredients']}',
      );
    }
  });

  test('compatible US units share one stock limit across recipe sections', () {
    final k = CreateKitchen(
      ingredients: ['1 cup of rice', '1 pound of carrots'],
      staples: [],
    );
    const idea = CreateIdea(
      title: 'Carrot rice',
      pitch: 'Cook carrots and rice together.',
      effort: 'Medium',
      minutes: 30,
      effortNote: 'Simmer until tender.',
      meal: 'Dinner',
      have: ['1 cup of rice', '1 pound of carrots'],
      staples: [],
      missing: [],
    );
    final dish = recipeD()
      ..addAll({
        'title': idea.title,
        'description': idea.pitch,
        'totalTime': '30 min',
        'notes': '',
        'steps': [
          'Prepare: Divide the carrots and rice between two small pots and cook until tender.',
        ],
        'ingredients': [
          ingredient('rice', '1/2', 'cup'),
          ingredient('rice', '8', 'tbsp'),
          ingredient('carrots', '3/4', 'lb'),
          ingredient('carrots', '4', 'oz')..['section'] = 'Second pot',
        ],
      });
    expect(validateRecipe(dish, k, idea)['title'], idea.title);
    dish['ingredients'][1]['amount'] = '9';
    expect(() => validateRecipe(dish, k, idea), throwsFormatException);
    dish['ingredients'][1]['amount'] = '8';
    dish['ingredients'][3]['amount'] = '5';
    expect(() => validateRecipe(dish, k, idea), throwsFormatException);
  });

  test('cup abbreviations normalize before stock and prose quantity checks', () {
    final k = CreateKitchen(ingredients: ['1 c. of brown rice'], staples: []);
    final idea = validateIdeas({
      'ideas': [ideaRow('Brown rice')],
    }, k, [], []).single;
    final dish = recipeD()
      ..['title'] = idea.title
      ..['ingredients'] = [
        ingredient('brown rice', '1/2', 'C.'),
        ingredient('brown rice', '8', 'tbsp')..['section'] = 'Second pan',
      ];
    final rows = validateRecipe(dish, k, idea)['ingredients'] as List;
    expect(rows.first['unit'], 'cup');
    expect(rows.first['amount'], '1/2');
    dish['ingredients'][1]['amount'] = '9';
    expect(() => validateRecipe(dish, k, idea), throwsFormatException);
    dish['ingredients'][1]['amount'] = '8';
    dish['steps'] = ['Simmer: Cook 2 c. of brown rice until tender.'];
    expect(() => validateRecipe(dish, k, idea), throwsFormatException);
  });

  test('dry spices have concrete names and their exclusions survive pantry matching', () {
    final k = CreateKitchen(
      ingredients: ['carrots'],
      staples: ['basic spices'],
      avoid: ['cumin'],
    );
    final ideas = validateIdeas({
      'ideas': [
        ideaRow('Skillet carrots', missing: ['ground cumin']),
        ideaRow('Roasted carrots', missing: ['smoked paprika']),
      ],
    }, k, [], []);
    expect(ideas.map((i) => i.title), ['Roasted carrots']);
    expect(ideas.single.staples, ['basic spices']);
    expect(ideas.single.missing, isEmpty);
    final spice = ingredient('basic spices', '1/2', 'tsp')
      ..['prepNote'] = 'smoked paprika';
    final dish = recipeD()
      ..['title'] = ideas.single.title
      ..['ingredients'] = [ingredient('carrots', '2'), spice];
    final checked = validateRecipe(dish, k, ideas.single);
    expect(checked['ingredients'][1], ingredient('smoked paprika', '1/2', 'tsp'));
    expect(spice['prepNote'], 'smoked paprika');
    for (final note in ['ground cumin', 'fresh parsley', 'to taste', '']) {
      spice['prepNote'] = note;
      expect(
        () => validateRecipe(dish, k, ideas.single, warnings: []),
        note == 'ground cumin' ? throwsA(isA<AvoidedRecipe>()) : throwsFormatException,
        reason: note,
      );
    }
    spice['name'] = 'fresh parsley';
    final warnings = <String>[];
    validateRecipe(dish, k, ideas.single, warnings: warnings);
    expect(warnings, ['Also uses fresh parsley.']);
  });

  test('whole countable foods agree with amounts without changing measured foods or mass nouns', () {
    final names = [
      ('eggs', '1', '', 'egg'), ('egg', '2', '', 'eggs'),
      ('large eggs', '1/2', '', 'large egg'),
      ('sweet potato', '1 1/2', '', 'sweet potatoes'),
      ('cherry tomatoes', '1', '', 'cherry tomato'),
      ('garlic cloves', '1', '', 'garlic clove'),
      ('onion', '2', 'medium', 'onions'),
      ('eggs', '1', 'cup', 'eggs'), ('beans', '1', 'can', 'beans'),
      ('salmon', '4', '', 'salmon'), ('couscous', '2', '', 'couscous'),
      ('cream of mushroom', '2', '', 'cream of mushroom'),
    ];
    for (final (food, amount, unit, expected) in names) {
      final k = CreateKitchen(ingredients: [food], staples: []);
      final idea = validateIdeas({
        'ideas': [ideaRow('Warm skillet')],
      }, k, [], []).single;
      final dish = recipeD()
        ..['title'] = idea.title
        ..['ingredients'] = [ingredient(food, amount, unit)];
      expect(
        validateRecipe(dish, k, idea)['ingredients'][0],
        ingredient(expected, amount, unit),
        reason: '$amount $unit $food',
      );
    }
  });

  test('whole peppers use vegetable stock while measured pepper uses the staple', () {
    final kitchen = CreateKitchen(ingredients: ['2 peppers'], staples: ['pepper']);
    final idea = validateIdeas({
      'ideas': [ideaRow('Roasted peppers', pantry: ['s1'])],
    }, kitchen, [], []).single;
    final dish = recipeD()
      ..['title'] = idea.title
      ..['ingredients'] = [
        ingredient('pepper', '2', 'medium'),
        ingredient('pepper', '1', 'tsp'),
      ];
    final rows = validateRecipe(dish, kitchen, idea)['ingredients'] as List;
    expect(rows.first['name'], 'peppers');
    expect(rows.last['name'], 'pepper');
    dish['ingredients'][0]['amount'] = '1';
    expect(validateRecipe(dish, kitchen, idea)['ingredients'][0]['name'], 'pepper');
    dish['ingredients'][0]['amount'] = '3';
    expect(() => validateRecipe(dish, kitchen, idea), throwsFormatException);
  });

  test('required ingredients, ingredient-only extras, structure and exclusions are checked', () {
    for (final edit in [
      (Json j) => (j['ingredients'] as List).removeAt(5),
      (Json j) =>
          (j['ingredients'] as List).add(ingredient('cilantro', '1', 'tsp')),
      (Json j) => (j['steps'] as List).add('aiGuessedFields'),
      (Json j) => j['notes'] = 'Offer soy sauce if desired.',
      (Json j) => (j['ingredients'][3] as Json)['prepNote'] = 'Mix with pesto.',
      (Json j) => j['servings'] = '5',
      (Json j) => j['totalTime'] = 'unknown',
    ]) {
      final dish = recipeD();
      edit(dish);
      // Flour tortillas contain wheat, so pesto is tested with a nut exclusion
      // and soy sauce with a soy exclusion, preserving an otherwise valid dish.
      final k = CreateKitchen(
        ingredients: kitchenD.ingredients,
        staples: kitchenD.staples,
        avoid: ['nuts', 'soy'],
      );
      expect(
        () => validateRecipe(dish, k, wraps),
        throwsFormatException,
        reason: dish.toString(),
      );
    }
  });

  test('only ingredient lines can trigger Also uses', () {
    final dish = recipeD()
      ..['steps'] = ['Simmer: Cook until the broth is clear.']
      ..['notes'] = 'The filling should be thick like honey.';
    final warnings = <String>[];
    validateRecipe(dish, kitchenD, wraps, warnings: warnings);
    expect(warnings, isEmpty);
    (dish['ingredients'] as List).add(ingredient('broth', '1', 'cup'));
    validateRecipe(dish, kitchenD, wraps, warnings: warnings);
    expect(warnings, ['Also uses broth.']);
  });

  test(
    'generated General and blank rows come first in their original order',
    () {
      final dish = recipeD();
      final rows = (dish['ingredients'] as List).cast<Json>();
      for (final row in rows) {
        row['section'] = 'Filling';
      }
      rows[1]['section'] = 'General Tso sauce';
      rows[3]['section'] = ' ';
      rows.last['section'] = ' gEnErAl ';
      final checked =
          (validateRecipe(dish, kitchenD, wraps)['ingredients'] as List)
              .cast<Json>();
      expect(checked.map((r) => r['name']), [
        rows[3]['name'],
        rows.last['name'],
        for (final i in [0, 1, 2, 4, 5]) rows[i]['name'],
      ]);
      expect(checked.map((r) => r['section']), [
        '',
        '',
        'Filling',
        'General Tso sauce',
        'Filling',
        'Filling',
        'Filling',
      ]);
      expect(rows.last['section'], ' gEnErAl ');
    },
  );

  test('dry seasonings and table pepper retain their pantry meanings', () {
    for (final name in [
      'ground cumin',
      'dried thyme',
      'ground ginger',
      'paprika',
      'garlic powder',
    ]) {
      expect(sameFood(name, 'basic spices'), isTrue, reason: name);
    }
    for (final name in [
      'fresh thyme',
      'fresh basil',
      'frozen oregano',
      'thyme sprigs',
      'fresh rosemary',
      'fresh ginger',
      'fresh turmeric',
      'garlic',
      'onions',
    ]) {
      expect(sameFood(name, 'basic spices'), isFalse, reason: name);
    }
    for (final name in [
      'fresh pepper',
      'peppers',
      'a pepper',
      '1 large pepper',
      'fresh diced pepper',
      'bell pepper',
      'chopped peppers',
    ]) {
      for (final pantry in ['pepper', 'black pepper', 'ground black pepper']) {
        expect(sameFood(name, pantry), isFalse, reason: '$name / $pantry');
      }
    }
    for (final (needed, pantry) in [
      ('fresh thyme', 'dried thyme'),
      ('fresh ginger', 'ground ginger'),
      ('olive oil', 'olive'),
      ('almond flour', 'flour'),
      ('peanut butter', 'butter'),
      ('garlic salt', 'salt'),
      ('brown sugar', 'sugar'),
    ]) {
      expect(sameFood(needed, pantry), isFalse, reason: needed);
    }
    expect(sameFood('fresh thyme', 'fresh thyme'), isTrue);
    expect(sameFood('dried pasta', 'pasta'), isTrue);
    expect(sameFood('ground cumin', 'cumin'), isTrue);
    expect(sameFood('ground black pepper', 'pepper'), isTrue);
    expect(sameFood('1 tsp pepper', 'black pepper'), isTrue);
    expect(distinctFoods(['pepper', '1 large pepper', 'peppers']), [
      'pepper',
      '1 large pepper',
    ]);
    final pepperIdea = validateIdeas(
      {
        'ideas': [
          ideaRow('Pepper rice', missing: ['pepper', 'peppers']),
        ],
      },
      CreateKitchen(ingredients: ['rice'], staples: ['black pepper']),
      [],
      [],
    ).single;
    expect(pepperIdea.missing, ['peppers']);
    expect(pepperIdea.staples, ['black pepper']);
    final photos = validatePhotos(
      {
        'found': ['fresh thyme', 'dried thyme', 'pepper', 'peppers'],
        'maybe': [],
      },
      [],
      ['basic spices', 'black pepper'],
    );
    expect(photos.found, ['fresh thyme', 'peppers']);
  });

  test(
    'generic directions and prepared spices resolve against selected foods',
    () {
      expect(sameFood('bread', 'flatbread'), isTrue);
      expect(sameFood('cheese', 'cheddar'), isTrue);
      expect(sameFood('fish', 'salmon'), isTrue);
      expect(sameFood('ground cumin', 'basic spices'), isTrue);
      final dish = recipeD()
        ..['steps'] = ['1. Fill: Roll up the four tortillas.'];
      expect(validateRecipe(dish, kitchenD, wraps)['steps'], [
        'Fill: Roll up the four tortillas.',
      ]);
    },
  );
}
