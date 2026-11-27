import 'dart:convert';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/smart_create_controller.dart';
import 'package:cookdex/smart_create_protocol.dart' show Json;
import 'package:cookdex/src/rust/api.dart' show Candidate;
import 'package:cookdex/src/rust/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/smart_create_replay.dart';
import 'import_service_test.dart' show ApiFake;
import 'smart_create_rules_test.dart' show kitchenD, recipeD, wraps;

class _RecipeBridge extends ApiFake {
  final writtenRecipes = <Json>[];

  @override
  Future<Candidate> crateApiSmartCreateCandidate({
    required String written,
  }) async {
    final data = jsonDecode(written) as Json;
    writtenRecipes.add(data);
    return candidate(data['title'] as String);
  }
}

void main() {
  late CreateReplayPlatform provider;
  late _RecipeBridge bridge;
  late LocalPreferences local;
  late SmartCreateController controller;

  setUp(() {
    provider = CreateReplayPlatform();
    bridge = _RecipeBridge();
    RustLib.initMock(api: bridge);
    local = LocalPreferences.memory();
    local.setCreatePreferences(
      local.createPreferences.copyWith(staples: kitchenD.staples),
    );
    controller = SmartCreateController(platform: provider, local: local);
    controller.ingredients = kitchenD.ingredients.toList();
  });

  tearDown(() {
    controller.dispose();
    local.dispose();
    RustLib.dispose();
  });

  for (final (label, markers, fields, indexes)
      in <(String, Json, List<String>, List<int>)>[
        ('missing', {}, [], []),
        (
          'non-list',
          {
            'aiGuessedFields': 'servings',
            'aiGuessedSteps': {'0': true},
          },
          [],
          [],
        ),
        (
          'mixed',
          {
            'aiGuessedFields': ['servings', 1, null, 'title', 'totalTime'],
            'aiGuessedSteps': [-1, 0, '1', 2, 4, null],
          },
          ['servings', 'totalTime'],
          [0, 2],
        ),
        (
          'one-based-looking',
          {
            'aiGuessedFields': [],
            'aiGuessedSteps': [1, 2, 3, 4],
          },
          [],
          [1, 2, 3],
        ),
      ]) {
    test('$label markers reach native validation after one request', () async {
      final dish = recipeD()
        ..['steps'] = [
          ...recipeD()['steps'] as List,
          'Serve: Put the warm wraps on plates.',
        ]
        ..remove('aiGuessedFields')
        ..remove('aiGuessedSteps')
        ..addAll(markers);
      provider.replies.add(dish);

      expect(await controller.recipe(wraps), isNotNull);
      expect(provider.requests, 1);
      expect(bridge.writtenRecipes, hasLength(1));
      final written = bridge.writtenRecipes.single;
      expect(written['aiGuessedFields'], fields);
      expect(written['aiGuessedSteps'], indexes);
      expect(written['ingredients'], dish['ingredients']);
      expect(written['steps'], dish['steps']);
      expect(controller.recipeWarning, isNull);
      expect(controller.error, isNull);
    });
  }
}
