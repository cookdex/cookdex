import 'dart:async';
import 'dart:io';

import 'package:cookdex/create_preferences.dart';
import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/smart_create_controller.dart';
import 'package:cookdex/ui/create_settings_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Service implements ImportService {
  @override
  final platform = _Platform();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform implements ImportPlatform {
  @override
  Future<SmartImportSettings> settings() async => SmartImportSettings(
    hasKey: true,
    model: 'import-model',
    effort: 'standard',
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'defaults migrate legacy Flash low while preserving other saved choices',
    () {
      const defaults = CreatePreferences.defaults();
      for (final step in CreateStep.values) {
        expect(defaults.modelFor(step), 'gemini-3.5-flash-lite');
        expect(defaults.thinkingFor(step), 'high');
      }
      final loaded = CreatePreferences.fromJson({
        'photoModel': 'gemini-3.5-flash-lite',
        'photoThinking': 'minimal',
        'ideaModel': 'gemini-3.8-flash',
        'ideaThinking': 'low',
        'recipeModel': 'gemini-3.1-pro-preview',
        'recipeThinking': 'high',
      });
      expect(loaded.photoThinking, 'minimal');
      expect(loaded.ideaModel, defaults.ideaModel);
      expect(loaded.ideaThinking, 'high');
      expect(loaded.usesRecommendedFor(CreateStep.ideas), isTrue);
      expect(loaded.usesRecommendedFor(CreateStep.photo), isFalse);
      expect(loaded.recipeThinking, 'high');
      final updated = loaded.withRetiredModel(
        CreateStep.recipe,
        loaded.recipeModel,
      );
      final restored = CreatePreferences.fromJson(updated.toJson());
      expect(restored.recipeModel, defaults.recipeModel);
      expect(restored.recipeThinking, 'high');
      expect(restored.retiredModelFor(CreateStep.recipe), loaded.recipeModel);
      expect(restored.photoModel, loaded.photoModel);
      expect(
        restored.withRetiredModel(CreateStep.photo, 'different'),
        same(restored),
      );
      expect(
        restored
            .withSelection(CreateStep.recipe, 'custom', 'default')
            .retiredModelFor(CreateStep.recipe),
        isNull,
      );
      expect(
        CreatePreferences.thinkingLevels('gemini-4-hydrogen'),
        containsAll(['default', 'low', 'medium', 'high']),
      );
      expect(
        CreatePreferences.thinkingLevels('gemini-4-hydrogen'),
        isNot(contains('minimal')),
      );
    },
  );

  test('existing local preferences gain defaults and retain explicit empty staples', () async {
    final dir = await Directory.systemTemp.createTemp(
      'cookdex-create-settings-',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/preferences.json');
    await file.writeAsString('{"query":"dinner"}');
    final prefs = await LocalPreferences.load(file.path);
    const defaults = CreatePreferences.defaults();
    expect(prefs.createPreferences.toJson(), defaults.toJson());
    final avoid = ['peanuts'];
    prefs.setCreatePreferences(
      defaults.copyWith(
        staples: [],
        avoid: avoid,
        otherPreferences: 'Prefer a crunchy topping',
        servings: 8,
        recipeModel: 'custom-pro',
        recipeThinking: 'default',
      ),
    );
    avoid.clear();
    await prefs.flush();
    final loaded = await LocalPreferences.load(file.path);
    expect(loaded.query, 'dinner');
    expect(loaded.createPreferences.staples, isEmpty);
    expect(loaded.createPreferences.avoid, ['peanuts']);
    expect(
      loaded.createPreferences.otherPreferences,
      'Prefer a crunchy topping',
    );
    expect(loaded.createPreferences.servings, 8);
    expect(loaded.createPreferences.recipeModel, 'custom-pro');
    expect(loaded.createPreferences.recipeThinking, 'default');
    prefs.dispose();
    await prefs.flush();
    loaded.dispose();
    await loaded.flush();
  });

  test('clearing Last Smart Create deletes its saved file', () async {
    final dir = await Directory.systemTemp.createTemp('cookdex-create-record-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/last-smart-create.json';
    await FileDraftStorage(path).write({'validation': 'Accepted'});
    final prefs = LocalPreferences.memory();
    addTearDown(prefs.dispose);
    final controller = SmartCreateController(
      platform: _Platform(),
      local: prefs,
      diagnostics: FileDraftStorage(path),
    );
    addTearDown(controller.dispose);
    expect(await controller.lastDiagnostic(), contains('Accepted'));
    await controller.clearDiagnostic();
    expect(await File(path).exists(), isFalse);
    expect(await FileDraftStorage(path).read(), isNull);
  });

  testWidgets('Create retains custom IDs and pending reset at maximum text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final prefs = LocalPreferences.memory();
    addTearDown(prefs.dispose);
    prefs.setCreatePreferences(
      prefs.createPreferences.copyWith(
        photoModel: 'synthetic-create-model',
        photoThinking: 'medium',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: CreateSettingsScreen(
          preferences: prefs,
          service: _Service(),
          onStaples: (_) async {},
          lastDiagnostic: () async => null,
          clearDiagnostic: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> tap(String label) async {
      final target = find.text(label).last;
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    final customField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Model ID',
    );
    await tap('Photo recognition');
    expect(
      tester.widget<TextField>(customField).controller!.text,
      'synthetic-create-model',
    );
    await tap('Reset to recommended');
    expect(find.text('High thinking'), findsOneWidget);
    expect(prefs.createPreferences.photoModel, 'synthetic-create-model');
    await tap('Cancel');
    expect(prefs.createPreferences.photoThinking, 'medium');
    await tap('Photo recognition');
    await tester.enterText(customField, ' another-create-model ');
    await tap('Save');
    expect(prefs.createPreferences.photoModel, 'another-create-model');
    expect(prefs.createPreferences.photoThinking, 'medium');
    expect(
      prefs.createPreferences.usesRecommendedFor(CreateStep.photo),
      isFalse,
    );
    expect(prefs.createPreferences.ideaModel, CreatePreferences.suggestedModel);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Create settings edit inputs independently and show local prompts and redacted debug',
    (tester) async {
      final prefs = LocalPreferences.memory();
      addTearDown(prefs.dispose);
      var reads = 0;
      var staplesOpened = 0;
      String? record = 'Status 400\nAIzaSyntheticSecret';
      final clearAttempt = Completer<void>();
      var clearAttempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: CreateSettingsScreen(
            preferences: prefs,
            service: _Service(),
            onStaples: (_) async {
              staplesOpened++;
            },
            lastDiagnostic: () async {
              reads++;
              return record;
            },
            clearDiagnostic: () async {
              if (++clearAttempts == 1) await clearAttempt.future;
              record = null;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        final target = find.text(label).last;
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Finder stepButton(String tooltip) => find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == tooltip,
      );
      Future<void> step(String tooltip) async {
        await tester.tap(stepButton(tooltip));
        await tester.pumpAndSettle();
      }

      expect(find.text('Key saved on this device'), findsOneWidget);
      await tap('Foods to avoid');
      expect(
        tester.widget<TextField>(find.byType(TextField)).textCapitalization,
        TextCapitalization.none,
      );
      await tester.enterText(find.byType(TextField), 'Peanuts');
      await tap('Save');
      expect(prefs.createPreferences.avoid, ['Peanuts']);
      await tap('Other preferences');
      expect(
        tester.widget<TextField>(find.byType(TextField)).textCapitalization,
        TextCapitalization.sentences,
      );
      await tester.enterText(find.byType(TextField), 'Prefer something smoky');
      expect(
        tester.getSemantics(find.byType(TextField)).label,
        contains('Other preferences'),
      );
      await tap('Save');
      expect(
        prefs.createPreferences.otherPreferences,
        'Prefer something smoky',
      );
      expect(prefs.createPreferences.avoid, ['Peanuts']);
      await tap('Other preferences');
      await tester.enterText(find.byType(TextField), 'A different preference');
      await tap('Cancel');
      expect(
        prefs.createPreferences.otherPreferences,
        'Prefer something smoky',
      );
      await tap('Staples');
      expect(staplesOpened, 1);
      expect(find.byType(AlertDialog), findsNothing);
      await tap('Default servings');
      expect(find.byType(TextField), findsNothing);
      await step('Fewer servings');
      await step('Fewer servings');
      await step('Fewer servings');
      expect(
        tester.widget<IconButton>(stepButton('Fewer servings')).onPressed,
        isNull,
      );
      await step('More servings');
      await tap('Save');
      expect(prefs.createPreferences.servings, 2);
      prefs.setCreatePreferences(
        prefs.createPreferences.copyWith(servings: 98),
      );
      await tester.pumpAndSettle();
      await tap('Default servings');
      await step('More servings');
      expect(
        tester.widget<IconButton>(stepButton('More servings')).onPressed,
        isNull,
      );
      await tap('Cancel');
      expect(prefs.createPreferences.servings, 98);
      expect(prefs.createPreferences.extraIngredients, 4);
      expect(find.text('Up to 4'), findsOneWidget);
      await tap('Items to buy per idea');
      expect(
        find.text(
          "The most ingredients you don't have that a Need a few things idea "
          "can call for. Staples don't count. Doesn't apply when you only "
          'type a mood.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      await step('Fewer items');
      await step('Fewer items');
      await step('Fewer items');
      expect(
        tester.widget<IconButton>(stepButton('Fewer items')).onPressed,
        isNull,
      );
      await tap('Cancel');
      expect(prefs.createPreferences.extraIngredients, 4);
      await tap('Items to buy per idea');
      await step('More items');
      await step('More items');
      expect(
        tester.widget<IconButton>(stepButton('More items')).onPressed,
        isNull,
      );
      await tap('Save');
      expect(prefs.createPreferences.extraIngredients, 6);
      expect(find.text('Up to 6'), findsOneWidget);
      expect(prefs.createPreferences.servings, 98);
      await tap('Photo recognition');
      await tap('Gemini 3.5 Flash-Lite');
      expect(find.text('Gemini 3.1 Pro preview (paid key)'), findsWidgets);
      expect(find.text('Gemini 4 Argon (paid key)'), findsNothing);
      await tap('Gemini 4 Hydrogen');
      await tap('High thinking');
      await tap('Low thinking');
      await tap('Save');
      expect(prefs.createPreferences.photoModel, 'gemini-4-hydrogen');
      expect(prefs.createPreferences.photoThinking, 'low');
      expect(
        prefs.createPreferences.usesRecommendedFor(CreateStep.photo),
        isFalse,
      );
      expect(prefs.createPreferences.recipeThinking, 'high');
      await tap('Photo recognition');
      await tap('Reset to recommended');
      expect(prefs.createPreferences.photoModel, 'gemini-4-hydrogen');
      await tap('Save');
      expect(prefs.createPreferences.photoModel, 'gemini-3.5-flash-lite');
      expect(prefs.createPreferences.photoThinking, 'high');
      expect(
        prefs.createPreferences.usesRecommendedFor(CreateStep.photo),
        isTrue,
      );
      expect(reads, 0);
      await tap('View prompts');
      expect(find.byType(SelectableText), findsNWidgets(4));
      expect(find.text('Recipe ideas — ingredients or photos'), findsOneWidget);
      expect(find.text('Recipe ideas — mood only'), findsOneWidget);
      await tap('Close');
      await tap('Last Smart Create');
      expect(reads, 1);
      expect(find.text('Status 400\n[redacted key]'), findsOneWidget);
      await tap('Close');
      await tap('Last Smart Create');
      expect(clearAttempts, 0);
      await tap('Clear record');
      for (final label in ['Clear record', 'Close']) {
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, label),
        );
        expect(button.onPressed, isNull);
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      clearAttempt.completeError(StateError('Synthetic clear failure'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not clear the last Smart Create.'),
        findsOneWidget,
      );
      expect(find.text('Status 400\n[redacted key]'), findsOneWidget);
      await tap('Clear record');
      expect(clearAttempts, 2);
      expect(find.byType(AlertDialog), findsNothing);
      // Let the previous failure notice uncover the settings row.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      await tap('Last Smart Create');
      expect(reads, 3);
      expect(find.text('No Smart Create has been recorded.'), findsOneWidget);
      expect(find.text('Clear record'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
