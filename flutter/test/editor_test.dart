import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

class EditorFake extends FakeRepository implements EditorRecipeRepository {
  EditorFake(super.recipes);
  List<String?>? inputs;
  Recipe? savedBase;
  int saves = 0;
  bool fail = false;
  Completer<RecipeFields>? normalizeGate;
  @override
  Future<RecipeFields> normalizeEditorFields(
    RecipeFields fields,
    List<String?> amountInputs,
  ) async {
    inputs = amountInputs;
    if (fields.title.trim().isEmpty) {
      throw const ServiceError(
        code: ErrorCode.validation,
        message: 'Give your recipe a name.',
      );
    }
    return normalizeGate == null ? fields : normalizeGate!.future;
  }

  @override
  Future<List<PastedIngredient>> parseIngredientPaste(
    String text,
    String section,
  ) async => [
    PastedIngredient(
      ingredient: Ingredient(
        amount: const Amount.rational(numerator: 1, denominator: 3),
        unit: 'cup',
        name: 'sugar',
        prepNote: '',
        optional: false,
        section: section,
      ),
      original: text,
    ),
  ];
  @override
  Future<CollectionSnapshot> save(
    int generation,
    Recipe? base,
    RecipeFields fields,
  ) async {
    saves++;
    savedBase = base;
    if (fail) {
      throw const ServiceError(
        code: ErrorCode.storage,
        message: 'Save failed.',
      );
    }
    if (base != null && recipes[base.id]?.revision != base.revision) {
      throw const ServiceError(
        code: ErrorCode.staleWrite,
        message: 'The collection changed. Refresh before saving.',
      );
    }
    changed(
      Recipe(
        id: base?.id ?? 'new-$saves',
        fields: fields,
        favorite: base?.favorite ?? false,
        createdAt: base?.createdAt ?? '2026-01-01',
        updatedAt: '2026-03-01',
        revision: (base?.revision ?? 0) + 1,
      ),
    );
    return current;
  }
}

class ClearFailureStorage extends MemoryDraftStorage {
  @override
  Future<void> clear() async => throw StateError('disk unavailable');
}

class DuplicateEditorFake extends EditorFake implements ImportRecipeRepository {
  DuplicateEditorFake(super.recipes);
  DuplicateChoice? choice;

  @override
  Future<CollectionSnapshot> importOne(
    int generation,
    RecipeFields fields,
    DuplicateChoice? choice,
  ) async {
    this.choice = choice;
    return save(
      generation,
      choice is DuplicateChoice_Replace ? recipes[choice.id] : null,
      fields,
    );
  }
}

Future<(EditorController, EditorFake, RecipeStore)> controller({
  Recipe? base,
  DraftStorage? storage,
  Map<String, dynamic>? recovered,
  List<Recipe>? recipes,
}) async {
  final repo = EditorFake(recipes ?? [?base]);
  final store = RecipeStore(repo, LocalPreferences.memory());
  await store.initialize();
  final c = await EditorController.create(
    store: store,
    storage: storage ?? MemoryDraftStorage(),
    base: base,
    recovered: recovered,
  );
  addTearDown(() {
    c.dispose();
    store.dispose();
  });
  return (c, repo, store);
}

Future<void> editor(
  WidgetTester tester,
  EditorController c, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool phoneFont = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var theme = cookdexTheme();
  if (phoneFont) {
    const family = 'EditorPhoneTestRoboto';
    await tester.runAsync(() async {
      final sdk = Platform.environment['FLUTTER_SDK']!;
      final loader = FontLoader(family);
      for (final weight in ['regular', 'bold']) {
        loader.addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)),
        );
      }
      await loader.load();
    });
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: family),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: family),
    );
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => RecipeEditor(
                  controller: c,
                  tagSuggestions: const ['Quick', 'Dinner'],
                  ingredientSuggestions: const ['Sugar', 'Salt'],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.byElementPredicate((element) {
  final widget = element.widget;
  if (widget is Semantics &&
      widget.properties.textField == true &&
      widget.properties.label == label) {
    // Populated resting cells paint their outline directly. Other idle fields
    // still have an InputDecorator; retain that existing target and never
    // substitute a semantic wrapper for an activated native TextField.
    var hasDecoratedOrNativeField = false;
    void inspect(Element child) {
      if (child.widget is InputDecorator || child.widget is TextField) {
        hasDecoratedOrNativeField = true;
      } else {
        child.visitChildElements(inspect);
      }
    }

    element.visitChildElements(inspect);
    return !hasDecoratedOrNativeField;
  }
  final decoration = switch (widget) {
    TextField() => widget.decoration,
    InputDecorator() => widget.decoration,
    _ => null,
  };
  if (decoration?.labelText != label && decoration?.hintText != label) {
    return false;
  }
  if (widget is InputDecorator) {
    var nativeAncestor = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is TextField) nativeAncestor = true;
      return !nativeAncestor;
    });
    return !nativeAncestor;
  }
  return true;
});

InputDecoration fieldDecoration(WidgetTester tester, Finder target) =>
    switch (tester.widget(target)) {
      TextField(:final decoration) => decoration!,
      InputDecorator(:final decoration) => decoration,
      _ => throw StateError('Expected an idle or active editor field'),
    };

TextStyle fieldStyle(WidgetTester tester, Finder target) => switch (tester
    .widget(target)) {
  TextField(:final style) => style!,
  InputDecorator(:final baseStyle) => baseStyle!,
  Semantics() =>
    tester
        .widget<Text>(find.descendant(of: target, matching: find.byType(Text)))
        .style!,
  _ => throw StateError('Expected an idle or active editor field'),
};

Future<void> enterFieldText(
  WidgetTester tester,
  Finder target,
  String text,
) async {
  if (tester.widget(target) is! TextField) {
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
  await tester.enterText(target, text);
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  bool found() {
    try {
      return target.evaluate().isNotEmpty;
    } on StateError {
      return false;
    }
  }

  if (!found()) {
    final form = find.byWidgetPredicate((w) => w is CustomScrollView).first;
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: form, matching: find.byType(Scrollable)).first,
    );
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    for (var i = 0; i < 80 && !found(); i++) {
      await tester.drag(form, const Offset(0, -240));
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

List<String> captureHaptics(WidgetTester tester) {
  final haptics = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      haptics.add(call.arguments as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return haptics;
}

void main() {
  testWidgets(
    'review labels identify guessed metadata and follow written steps',
    (tester) async {
      final (c, _, _) = await controller();
      c.draft.aiGuessedFields.addAll(['servings', 'totalTime', 'tags']);
      c.draft.steps.first.aiGuess = true;
      c.draft.steps.first.text = 'Mix ingredients.';
      c.draft.steps.add(EditableStep('Original instruction.'));
      await editor(tester, c);
      await reveal(tester, find.text('AI guess').first);
      expect(find.text('AI guess'), findsNWidgets(2));
      expect(find.text('Total time: AI guess'), findsOneWidget);
      await reveal(tester, find.text('AI-written'));
      expect(find.text('AI-written'), findsOneWidget);
      c.reorder(c.draft.steps, 0, 1);
      await tester.pumpAndSettle();
      expect(c.draft.steps.last.aiGuess, true);
      await reveal(tester, find.text('AI guess').first);
      expect(find.text('AI guess'), findsNWidgets(2));
      expect(find.text('Total time: AI guess'), findsOneWidget);
      await reveal(tester, find.text('AI-written'));
      expect(find.text('AI-written'), findsOneWidget);
      c.draft.aiGuessedFields.clear();
      for (final step in c.draft.steps) {
        step.aiGuess = false;
      }
      c.changed();
      await tester.pumpAndSettle();
      expect(find.text('AI guess'), findsNothing);
      expect(find.text('AI-written'), findsNothing);
      expect(find.text('Total time: AI guess'), findsNothing);
    },
  );
  testWidgets('new and recovered imports use the review title', (tester) async {
    final (c, _, _) = await controller();
    c.draft.imported = true;
    await editor(tester, c);
    expect(find.text('Review import'), findsOneWidget);
    expect(find.text('Write a recipe'), findsNothing);

    final (recovered, _, _) = await controller(recovered: c.draft.toJson());
    await tester.pumpWidget(const SizedBox.shrink());
    await editor(tester, recovered);
    expect(find.text('Review import'), findsOneWidget);
    expect(find.text('Write a recipe'), findsNothing);
  });
  testWidgets('manual recipes keep their write and edit titles', (
    tester,
  ) async {
    final (fresh, _, _) = await controller();
    await editor(tester, fresh);
    expect(find.text('Write a recipe'), findsOneWidget);
    expect(find.text('Review import'), findsNothing);

    final (existing, _, _) = await controller(
      base: recipe('existing', title: 'Soup'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await editor(tester, existing);
    expect(find.text('Edit recipe'), findsOneWidget);
    expect(find.text('Review import'), findsNothing);
  });
  test('suggestions rank usage with stable ties and case-insensitive deduplication', () {
    expect(rankEditorSuggestions(['salt', 'Sugar', 'SALT', 'flour', 'Sugar']), [
      'salt',
      'Sugar',
      'flour',
    ]);
    expect(
      rankEditorSuggestions(['Quick', 'Dinner', 'QUICK'], lowercase: true),
      ['quick', 'dinner'],
    );
  });
  testWidgets(
    '320dp ingredient hints and one-line controls fit with full touch targets',
    (tester) async {
      final (c, _, _) = await controller();
      await editor(tester, c, size: const Size(320, 844), phoneFont: true);
      await reveal(tester, field('Ingredient').first);
      for (final label in ['Amount', 'Unit', 'Ingredient']) {
        final decoration = fieldDecoration(tester, field(label).first);
        final bounds = tester.getRect(field(label).first);
        final hint = TextPainter(
          text: TextSpan(text: label, style: decoration.hintStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(hint.width, lessThanOrEqualTo(bounds.width - 16));
        hint.dispose();
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label).first)
              .didExceedMaxLines,
          isFalse,
        );
      }
      final drag = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Reorder ingredient 1',
        ),
      );
      final delete = tester.getRect(find.byTooltip('Delete ingredient 1'));
      final note = tester.getRect(
        find.widgetWithText(TextButton, '+ Note').first,
      );
      final optional = tester.getRect(
        find
            .ancestor(
              of: find.text('Optional').first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(note.top, drag.top);
      expect(delete.top, drag.top);
      expect(optional.top, delete.top);
      for (final target in [note, drag, optional, delete]) {
        expect(target.left, greaterThanOrEqualTo(0));
        expect(target.right, lessThanOrEqualTo(320));
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
      }
      expect(
        tester.getRect(find.text('Optional').first).right + 12,
        lessThanOrEqualTo(delete.left),
      );
      expect(
        drag.top,
        greaterThanOrEqualTo(tester.getRect(field('Ingredient').first).bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'one suggestion strip stays above keyboard through scrolling and controls',
    (tester) async {
      final (c, _, _) = await controller();
      await editor(tester, c);
      await reveal(tester, field('Unit').first);
      await tester.tap(field('Unit').first);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final strip = find.byKey(const ValueKey('editor-suggestion-strip'));
      expect(strip, findsOneWidget);
      expect(tester.getRect(strip).bottom, 844 - 260);
      expect(find.byType(RawAutocomplete<String>), findsNothing);
      await tester.drag(
        find.byWidgetPredicate((w) => w is CustomScrollView).first,
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(strip, findsOneWidget);
      await reveal(tester, find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(strip, findsOneWidget);
      await reveal(tester, field('Unit').first);
      await enterFieldText(tester, field('Unit').first, 'tb');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ActionChip, 'tbsp'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'tsp'), findsNothing);
      await tester.tap(find.widgetWithText(ActionChip, 'tbsp'));
      await tester.pumpAndSettle();
      expect(c.draft.sections.single.rows.first.unit, 'tbsp');
      expect(strip, findsOneWidget);
      await enterFieldText(tester, field('Unit').first, 'handful');
      await tester.pumpAndSettle();
      expect(c.draft.sections.single.rows.first.unit, 'handful');
      expect(strip, findsOneWidget);
      expect(tester.getSize(strip).width, 390);
      expect(find.byType(ActionChip), findsNothing);
      await tester.tap(field('Ingredient').first);
      await tester.pumpAndSettle();
      expect(strip, findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      expect(strip, findsNothing);
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(strip, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'collection usage ranks units names and preferred tag spellings before standards',
    (tester) async {
      final first = recipe('first');
      first.fields.ingredients.clear();
      first.fields.ingredients.addAll([
        const Ingredient(
          amount: Amount.toTaste(),
          unit: 'kg',
          name: 'salt',
          prepNote: '',
          optional: false,
          section: '',
        ),
        const Ingredient(
          amount: Amount.toTaste(),
          unit: 'cup',
          name: 'sugar',
          prepNote: '',
          optional: false,
          section: '',
        ),
      ]);
      final second = recipe('second');
      second.fields.ingredients.clear();
      second.fields.ingredients.add(
        const Ingredient(
          amount: Amount.toTaste(),
          unit: 'kg',
          name: 'sugar',
          prepNote: '',
          optional: false,
          section: '',
        ),
      );
      second.fields.tags.add('Dinner');
      final (c, repo, _) = await controller(recipes: [first, second]);
      await editor(tester, c);
      await reveal(tester, field('Unit').first);
      await tester.tap(field('Unit').first);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      List<String> chips() => tester
          .widgetList<ActionChip>(find.byType(ActionChip))
          .map((chip) => (chip.label as Text).data!)
          .toList();
      expect(chips().take(3), ['kg', 'cup', 'tbsp']);
      expect(repo.detailCalls, 2);
      await tester.tap(field('Ingredient').first);
      await tester.pumpAndSettle();
      expect(chips(), ['sugar', 'salt']);
      await reveal(tester, field('Add tag'));
      await tester.tap(field('Add tag'));
      await tester.pumpAndSettle();
      expect(chips(), ['Quick', 'Dinner']);
      await tester.tap(find.widgetWithText(ActionChip, 'Quick'));
      await tester.pumpAndSettle();
      expect(c.draft.tags, ['Quick']);
      expect(chips(), ['Dinner']);
      expect(repo.detailCalls, 2);
    },
  );
  test(
    'C7 recovered row captures its unit baseline before subsequent edits',
    () {
      final row = EditableIngredient.fromJson({
        'id': 'old',
        'amount': '1',
        'unit': 'Tablespoons',
        'name': 'butter',
        'prepNote': '',
        'optional': false,
        'originalAmount': {
          'kind': 'rational',
          'numerator': 1,
          'denominator': 1,
        },
        'originalText': '1',
      });
      expect(row.originalUnit, 'Tablespoons');
      row.unit = 'T';
      expect(row.originalUnit, 'Tablespoons');
      expect(
        EditableIngredient.fromJson(row.toJson()).originalUnit,
        'Tablespoons',
      );
    },
  );
  test(
    'save keeps Rust unit normalization for unchanged and pasted units',
    () async {
      final original = recipe('a');
      final ingredient = original.fields.ingredients.single;
      original.fields.ingredients[0] = Ingredient(
        amount: ingredient.amount,
        unit: 'Tablespoons',
        name: ingredient.name,
        prepNote: ingredient.prepNote,
        optional: ingredient.optional,
        section: ingredient.section,
      );
      final (c, repo, _) = await controller(base: original);
      final row = c.draft.sections.single.rows.single;
      expect(row.unit, 'Tablespoons');
      expect(row.originalUnit, 'Tablespoons');
      expect(c.dirty, false);
      final input = c.draft.fields();
      final normalized = RecipeFields(
        title: input.title,
        description: input.description,
        servings: input.servings,
        prepTime: input.prepTime,
        cookTime: input.cookTime,
        totalTime: input.totalTime,
        source: input.source,
        tags: input.tags,
        notes: input.notes,
        steps: input.steps,
        ingredients: [
          Ingredient(
            amount: input.ingredients.single.amount,
            unit: 'tbsp',
            name: 'butter',
            prepNote: '',
            optional: false,
            section: '',
          ),
        ],
      );
      repo.normalizeGate = Completer<RecipeFields>()..complete(normalized);
      final saved = await c.save();
      expect(saved!.fields.ingredients.single.unit, 'tbsp');
      expect(repo.inputs, [null]);
      expect(repo.savedBase!.fields.ingredients.single.unit, 'Tablespoons');
      final (paste, pasteRepo, _) = await controller();
      paste.draft.title = 'Pasted';
      final section = paste.draft.sections.single;
      await paste.applyIngredients([
        PastedIngredient(
          ingredient: normalized.ingredients.single,
          original: '1 tbsp butter',
        ),
      ], section);
      paste.draft.sections.single.rows.single.unit = 'TB';
      pasteRepo.normalizeGate = Completer<RecipeFields>()..complete(normalized);
      final pasted = await paste.save();
      expect(pasted!.fields.ingredients.single.unit, 'tbsp');
    },
  );

  test('raw draft roundtrip preserves base exact quantities, source, errors and paste', () {
    final original = recipe('original');
    final d = EditorDraft.fromRecipe(original, ['33/100']);
    d.source = 'https://example.test/source';
    d.error = 'Save failed.';
    d.sections.single.rows.single.amount = '0.33';
    d.pasteKind = 'ingredients';
    d.pasteSectionId = d.sections.single.id;
    d.pasteText = '0.33 cup sugar';
    final reopened = EditorDraft.fromJson(
      jsonDecode(jsonEncode(d.toJson())) as Map<String, dynamic>,
    );
    expect(recipeToJson(reopened.base!), recipeToJson(original));
    expect(
      reopened.sections.single.rows.single.originalAmount,
      const Amount.rational(numerator: 33, denominator: 100),
    );
    expect(reopened.amountInputs(), ['0.33']);
    expect(reopened.source, d.source);
    expect(reopened.error, d.error);
    expect(reopened.pasteText, d.pasteText);
  });
  test('unchanged and reverted amount bypass parsing; new written decimal delegates to Rust', () async {
    final (c, repo, _) = await controller(base: recipe('original'));
    final row = c.draft.sections.single.rows.single;
    expect(c.draft.amountInputs(), [null]);
    row.amount = '0.33';
    expect(c.draft.amountInputs(), ['0.33']);
    row.amount = '33/100';
    c.changed();
    await c.save();
    expect(repo.inputs, [null]);
    expect(
      repo.recipes['original']!.fields.ingredients.single.amount,
      const Amount.rational(numerator: 33, denominator: 100),
    );
  });
  test(
    'failed save persists raw draft, source and error; relaunch can retry',
    () async {
      final storage = MemoryDraftStorage();
      final (c, repo, store) = await controller(storage: storage);
      c.draft.title = 'Dinner';
      c.draft.source = 'https://example.test/dinner';
      c.draft.sections.single.rows.single.amount = '0.33';
      c.draft.sections.single.rows.single.name = 'Sugar';
      c.changed();
      repo.fail = true;
      expect(await c.save(), isNull);
      await c.flush();
      final restored = await EditorController.create(
        store: store,
        storage: storage,
        recovered: await storage.read(),
      );
      addTearDown(restored.dispose);
      expect(restored.draft.error, 'Save failed.');
      expect(restored.draft.source, c.draft.source);
      expect(restored.draft.sections.single.rows.single.amount, '0.33');
      expect(restored.dirty, true);
      repo.fail = false;
      expect(await restored.save(), isNotNull);
      expect(await storage.read(), isNull);
    },
  );
  test('changed and deleted originals recover as new copies', () async {
    for (final deleted in [false, true]) {
      final base = recipe('original');
      final draft = EditorDraft.fromRecipe(base, ['33/100']);
      draft.title = 'My draft';
      final (c, repo, _) = await controller(
        recovered: draft.toJson(),
        recipes: deleted ? [] : [recipe('original', revision: 2)],
      );
      expect(c.draft.stale, true);
      final saved = await c.save();
      expect(saved!.id, isNot('original'));
      expect(repo.savedBase, isNull);
      if (!deleted) expect(repo.recipes['original']!.revision, 2);
    }
  });
  test(
    'original changed during editing fails first save then saves copy',
    () async {
      final (c, repo, store) = await controller(base: recipe('original'));
      c.draft.title = 'My version';
      c.changed();
      repo.changed(recipe('original', revision: 2));
      await store.refresh();
      expect(await c.save(), isNull);
      expect(c.draft.stale, true);
      expect(c.draft.error, isNull);
      final copied = await c.save();
      expect(copied!.id, isNot('original'));
      expect(repo.savedBase, isNull);
    },
  );
  test(
    'recovery clears only the known stale warning for a changed original',
    () async {
      final base = recipe('original');
      const staleMessage = 'The collection changed. Refresh before saving.';
      for (final changed in [false, true]) {
        for (final message in [staleMessage, 'Save failed.']) {
          final draft = EditorDraft.fromRecipe(base, ['33/100']);
          draft.title = 'My version';
          draft.error = message;
          final (c, _, _) = await controller(
            recovered: draft.toJson(),
            recipes: [recipe('original', revision: changed ? 2 : 1)],
          );
          expect(c.draft.stale, changed);
          expect(
            c.draft.error,
            changed && message == staleMessage ? isNull : message,
          );
          expect(c.draft.title, 'My version');
        }
      }
    },
  );

  testWidgets(
    'stale copy banner appears once and keeps unrelated save errors',
    (tester) async {
      final (c, repo, store) = await controller(base: recipe('original'));
      c.draft.title = 'My version';
      c.changed();
      repo.changed(recipe('original', revision: 2));
      await store.refresh();
      expect(await c.save(), isNull);
      await editor(tester, c);
      expect(
        find.text('Original changed. Save this draft as a copy.'),
        findsOneWidget,
      );
      expect(
        find.text('The collection changed. Refresh before saving.'),
        findsNothing,
      );
      expect(find.text('Save copy'), findsOneWidget);
      repo.fail = true;
      expect(await c.save(), isNull);
      await tester.pumpAndSettle();
      expect(
        find.text('Original changed. Save this draft as a copy.'),
        findsOneWidget,
      );
      expect(find.text('Save failed.'), findsOneWidget);
    },
  );

  test('unapplied paste and tag input block Save before any normalization or mutation', () async {
    final (c, repo, _) = await controller();
    c.draft.title = 'Dinner';
    c.draft.pasteKind = 'steps';
    c.draft.pasteText = 'Mix';
    c.changed();
    expect(await c.save(), isNull);
    expect(repo.inputs, isNull);
    expect(repo.saves, 0);
    c.clearPaste();
    c.draft.tagInput = 'Quick';
    c.changed();
    expect(await c.save(), isNull);
    expect(repo.saves, 0);
    c.addTag('quick', ['Quick']);
    expect(c.draft.tags, ['quick']);
    expect(c.draft.tagInput, '');
  });
  test('save rejects stale normalization results', () async {
    final (c, repo, _) = await controller();
    c.draft.title = 'Before';
    c.changed();
    final before = c.draft.fields();
    repo.normalizeGate = Completer<RecipeFields>();
    final saving = c.save();
    c.draft.title = 'After';
    c.changed();
    repo.normalizeGate!.complete(before);
    expect(await saving, isNull);
    expect(repo.saves, 0);
    expect(c.draft.title, 'After');
  });
  test(
    'completed draft tombstone avoids duplicates after clear failure',
    () async {
      final storage = ClearFailureStorage();
      final (c, repo, store) = await controller(storage: storage);
      c.draft.title = 'Saved';
      c.changed();
      final saved = await c.save();
      expect(saved, isNotNull);
      expect(c.dirty, false);
      expect(c.persistenceError, isNotNull);
      final restored = await EditorController.create(
        store: store,
        storage: storage,
        recovered: await storage.read(),
      );
      addTearDown(restored.dispose);
      expect(restored.dirty, false);
      expect(restored.draft.base!.id, saved!.id);
      expect(restored.draft.stale, false);
      expect(repo.saves, 1);
    },
  );
  test(
    'paste section order, optional prep and Undo retain identities',
    () async {
      final (c, _, _) = await controller();
      final target = c.draft.sections.single;
      final rows = [
        for (final name in ['Sauce', 'Topping'])
          PastedIngredient(
            ingredient: Ingredient(
              amount: const Amount.toTaste(),
              unit: '',
              name: 'salt',
              prepNote: 'fine',
              optional: true,
              section: name,
            ),
            original: 'salt',
          ),
      ];
      await c.applyIngredients(rows, target);
      expect(c.draft.sections.map((s) => s.name), ['', 'Sauce', 'Topping']);
      final row = c.draft.sections[1].rows.single;
      expect(row.optional, true);
      expect(row.prepNote, 'fine');
      final undo = c.remove(c.draft.sections[1].rows, row);
      undo();
      undo();
      expect(c.draft.sections[1].rows, [row]);
      c.move(c.draft.sections, target, 1);
      expect(c.draft.sections[1], same(target));
      c.reorder(c.draft.sections, 1, 2);
      expect(c.draft.sections[2], same(target));
    },
  );
  test(
    'paste steps handles numbered multiline, paragraphs and single lines',
    () {
      expect(splitPastedSteps('1. Mix\n  until smooth\n2. Bake'), [
        'Mix\n  until smooth',
        'Bake',
      ]);
      expect(splitPastedSteps('Mix\nwell\n\nBake'), ['Mix\nwell', 'Bake']);
      expect(splitPastedSteps('Mix\nBake'), ['Mix', 'Bake']);
    },
  );
  testWidgets(
    'no autofocus, title Enter does not Save, dirty Back can cancel or discard',
    (tester) async {
      final (c, repo, _) = await controller();
      await editor(tester, c);
      expect(tester.testTextInput.isVisible, false);
      await enterFieldText(tester, field('Title'), 'My dinner');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(repo.saves, 0);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.draft.title, 'My dinner');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(await c.storage.read(), isNull);
    },
  );
  testWidgets('tag Enter matches case and never saves the recipe', (
    tester,
  ) async {
    final (c, repo, _) = await controller();
    await editor(tester, c);
    await reveal(tester, field('Add tag'));
    await enterFieldText(tester, field('Add tag'), 'quick');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.draft.tags, ['quick']);
    expect(c.draft.tagInput, '');
    expect(repo.saves, 0);
  });
  testWidgets(
    'ingredient optional, note, standard units, accessible reorder and Undo',
    (tester) async {
      final (c, _, _) = await controller();
      final section = c.draft.sections.single;
      section.rows.first.name = 'First';
      section.rows.add(EditableIngredient(name: 'Second'));
      await editor(tester, c, size: const Size(800, 1800));
      await reveal(tester, find.byType(Checkbox).first);
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      expect(section.rows.first.optional, true);
      await reveal(tester, find.text('+ Note').first);
      await tester.tap(find.text('+ Note').first);
      await tester.pumpAndSettle();
      await enterFieldText(tester, field('Prep note').first, 'finely chopped');
      expect(section.rows.first.prepNote, 'finely chopped');
      await reveal(tester, field('Unit').first);
      await enterFieldText(tester, field('Unit').first, 'tb');
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(find.text('tbsp'), findsOneWidget);
      await tester.tap(find.text('tbsp'));
      await tester.pumpAndSettle();
      expect(section.rows.first.unit, 'tbsp');
      final reorder = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(ValueKey(section.rows.first.id)),
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.customSemanticsActions?.keys.any(
                          (a) => a.label == 'Move down',
                        ) ==
                        true,
              ),
            )
            .first,
      );
      reorder.properties.customSemanticsActions!.entries
          .firstWhere((e) => e.key.label == 'Move down')
          .value();
      await tester.pumpAndSettle();
      expect(section.rows.map((r) => r.name), ['Second', 'First']);
      await tester.tap(find.byTooltip('Delete ingredient 1'));
      await tester.pumpAndSettle();
      expect(section.rows.length, 1);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(section.rows.length, 2);
    },
  );
  testWidgets(
    'closed paste persists, blocks Save and section deletion, then applies reviewed steps',
    (tester) async {
      final (c, repo, _) = await controller();
      c.draft.title = 'Dinner';
      await editor(tester, c, size: const Size(800, 1800));
      await reveal(tester, find.text('Paste ingredients'));
      await tester.tap(find.text('Paste ingredients'));
      await tester.pumpAndSettle();
      await enterFieldText(tester, field('Ingredients'), '0.33 cup sugar');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(c.draft.unappliedPaste, true);
      await reveal(tester, find.byTooltip('Section 1 options'));
      await tester.tap(find.byTooltip('Section 1 options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete section'));
      await tester.pumpAndSettle();
      expect(c.draft.sections.length, 1);
      await c.flush();
      expect((await c.storage.read())!['pasteText'], '0.33 cup sugar');
      c.clearPaste();
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Paste steps'));
      await tester.tap(find.text('Paste steps'));
      await tester.pumpAndSettle();
      await enterFieldText(tester, field('Steps'), '1. Mix\n2. Bake');
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.text('Apply'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(c.draft.steps.map((s) => s.text), ['Mix', 'Bake']);
      expect(c.draft.unappliedPaste, false);
    },
  );
  testWidgets('real nested ingredient and step drag plus step deletion Undo', (
    tester,
  ) async {
    final haptics = captureHaptics(tester);
    final (c, _, _) = await controller();
    final section = c.draft.sections.single;
    section.rows.first.name = 'First';
    section.rows.add(EditableIngredient(name: 'Second'));
    c.draft.steps.clear();
    c.draft.steps.addAll([EditableStep('Mix'), EditableStep('Bake')]);
    await editor(tester, c, size: const Size(800, 2200));
    final first = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Reorder ingredient 1',
    );
    final second = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Reorder ingredient 2',
    );
    await reveal(tester, first);
    final ingredientDestination = Offset(
      tester.getCenter(first).dx,
      tester.getTopLeft(find.byKey(ValueKey(section.rows[0].id))).dy - 10,
    );
    var gesture = await tester.startGesture(tester.getCenter(second));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      haptics.where((value) => value == 'HapticFeedbackType.lightImpact'),
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      haptics.where((value) => value == 'HapticFeedbackType.lightImpact'),
      hasLength(1),
    );
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 100));
    final ingredientStart = tester.getCenter(second) - const Offset(0, 30);
    for (var n = 1; n <= 12; n++) {
      await gesture.moveTo(
        Offset.lerp(ingredientStart, ingredientDestination, n / 12)!,
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(section.rows.map((r) => r.name), ['Second', 'First']);
    final step1 = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Reorder step 1',
    );
    final step2 = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Reorder step 2',
    );
    await reveal(tester, step1);
    final stepDestination = Offset(
      tester.getCenter(step1).dx,
      tester.getTopLeft(find.byKey(ValueKey(c.draft.steps[0].id)).first).dy -
          10,
    );
    gesture = await tester.startGesture(tester.getCenter(step2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      haptics.where((value) => value == 'HapticFeedbackType.lightImpact'),
      hasLength(2),
    );
    await gesture.moveBy(const Offset(0, -30));
    await tester.pump(const Duration(milliseconds: 100));
    final stepStart = tester.getCenter(step2) - const Offset(0, 30);
    for (var n = 1; n <= 12; n++) {
      await gesture.moveTo(Offset.lerp(stepStart, stepDestination, n / 12)!);
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(c.draft.steps.map((s) => s.text), ['Bake', 'Mix']);
    await tester.tap(find.byKey(ValueKey('${c.draft.steps.first.id}-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete step 1'));
    await tester.pumpAndSettle();
    expect(c.draft.steps.map((s) => s.text), ['Mix']);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(c.draft.steps.map((s) => s.text), ['Bake', 'Mix']);
  });
  testWidgets(
    'quick swipes across reorder handles scroll without a reorder or light haptic',
    (tester) async {
      final haptics = captureHaptics(tester);
      final (c, _, _) = await controller();
      final section = c.draft.sections.single;
      section.rows.clear();
      section.rows.addAll(
        List.generate(
          8,
          (i) => EditableIngredient(name: 'Ingredient ${i + 1}'),
        ),
      );
      c.draft.steps.clear();
      c.draft.steps.addAll(
        List.generate(8, (i) => EditableStep('Step ${i + 1} instructions')),
      );
      final ingredientIds = section.rows.map((row) => row.id).toList();
      final stepIds = c.draft.steps.map((step) => step.id).toList();
      await editor(tester, c, phoneFont: true);
      final form = find
          .byWidgetPredicate(
            (widget) =>
                widget is CustomScrollView &&
                widget.scrollDirection == Axis.vertical,
          )
          .first;
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: form, matching: find.byType(Scrollable)).first,
      );
      for (final label in ['Reorder ingredient 1', 'Reorder step 1']) {
        final handle = find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == label,
        );
        await reveal(tester, handle);
        final before = scroll.position.pixels;
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await tester.pump(const Duration(milliseconds: 60));
        await gesture.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveBy(const Offset(0, -100));
        await tester.pump(const Duration(milliseconds: 60));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scroll.position.pixels, greaterThan(before), reason: label);
        expect(section.rows.map((row) => row.id), ingredientIds);
        expect(c.draft.steps.map((step) => step.id), stepIds);
        expect(
          haptics.where((value) => value == 'HapticFeedbackType.lightImpact'),
          isEmpty,
          reason: label,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'phone editor groups time fields below Makes and keeps ingredient rows compact',
    (tester) async {
      final (c, _, _) = await controller();
      final section = c.draft.sections.single;
      section.rows.addAll(
        List.generate(
          4,
          (i) => EditableIngredient(name: 'Ingredient ${i + 2}'),
        ),
      );
      await editor(tester, c, phoneFont: true);
      expect(
        tester.getTopLeft(field('Makes')).dy,
        lessThan(tester.getTopLeft(field('Total time')).dy),
      );
      expect(
        tester.getTopLeft(field('Prep time')).dy,
        tester.getTopLeft(field('Cook time')).dy,
      );
      expect(
        tester.getTopLeft(field('Makes')).dx,
        lessThan(tester.getTopLeft(field('Total time')).dx),
      );
      expect(find.text('Ingredients'), findsOneWidget);
      expect(find.byTooltip('Ingredient 1 options'), findsNothing);
      expect(find.byTooltip('Step 1 options'), findsNothing);
      await reveal(tester, field('Ingredient').first);
      final noteBounds = tester.getRect(
        find.widgetWithText(TextButton, '+ Note').first,
      );
      final deleteBounds = tester.getRect(
        find.byTooltip('Delete ingredient 1'),
      );
      expect(noteBounds.height, 48);
      expect(deleteBounds.height, 48);
      expect(deleteBounds.top, noteBounds.top);
      expect(
        tester.getSize(find.byKey(ValueKey(section.rows.first.id))).height,
        // Fields and one action row, plus existing padding and divider.
        tester.getSize(field('Ingredient').first).height + 48 + 21,
      );
      final amount = tester.getRect(field('Amount').first);
      final ingredient = tester.getRect(field('Ingredient').first);
      expect(amount.top, ingredient.top);
      expect(
        fieldDecoration(tester, field('Ingredient').first).labelText,
        isNull,
      );
      expect(find.text('Step 1'), findsNothing);
      for (final label in ['Amount', 'Unit', 'Ingredient']) {
        expect(
          find.byWidgetPredicate(
            (widget) => widget is Semantics && widget.properties.label == label,
          ),
          findsWidgets,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'phone ingredient notes sit above stable controls and units fit their abbreviations',
    (tester) async {
      final (c, _, _) = await controller();
      final rows = c.draft.sections.single.rows;
      rows.first.name = 'Garlic';
      rows.first.unit = 'clove';
      rows.add(EditableIngredient(name: 'Flour', unit: 'cup'));
      await editor(tester, c, phoneFont: true);
      await reveal(tester, find.byType(Checkbox).first);
      // Revealing the checkbox may scroll a narrow controls row. Align both
      // controls viewports at the end so Delete stays inside the card edge.
      for (final checkbox in find.byType(Checkbox).evaluate()) {
        final scroll = Scrollable.maybeOf(checkbox, axis: Axis.horizontal);
        scroll?.position.jumpTo(scroll.position.maxScrollExtent);
      }
      await tester.pumpAndSettle();
      final optionalBefore = tester.getTopLeft(find.byType(Checkbox).first);
      final deleteBefore = tester.getTopLeft(
        find.byTooltip('Delete ingredient 1'),
      );
      final amount = tester.getRect(field('Amount').first);
      final unit = tester.getRect(field('Unit').first);
      final name = tester.getRect(field('Ingredient').first);
      expect(unit.width, greaterThanOrEqualTo(64));
      expect(name.width, greaterThan(unit.width));
      for (final abbreviation in ['tbsp', 'cup', 'clove']) {
        final text = TextPainter(
          text: TextSpan(
            text: abbreviation,
            style: fieldStyle(tester, field('Unit').first),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        expect(text.width, lessThanOrEqualTo(unit.width - 16));
        text.dispose();
      }
      await tester.tap(find.text('+ Note').first);
      await tester.pumpAndSettle();
      await enterFieldText(tester, field('Prep note').first, 'finely chopped');
      await tester.pumpAndSettle();
      final note = tester.getRect(field('Prep note').first);
      final optionalAfter = tester.getTopLeft(find.byType(Checkbox).first);
      final deleteAfter = tester.getTopLeft(
        find.byTooltip('Delete ingredient 1'),
      );
      expect(note.left, amount.left);
      // Flooring the horizontal scroll endpoint to a physical pixel leaves
      // less than one pixel of the controls row beyond the viewport edge.
      expect(
        note.right,
        closeTo(deleteAfter.dx + 48, 1 / tester.view.devicePixelRatio),
      );
      expect(note.top, greaterThanOrEqualTo(name.bottom));
      expect(note.bottom, lessThanOrEqualTo(optionalAfter.dy));
      expect(optionalAfter.dx, optionalBefore.dx);
      expect(deleteAfter.dx, deleteBefore.dx);
      expect(find.text('+ Note'), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(Checkbox).last).dx,
        optionalAfter.dx,
      );
      final noteStyle = fieldStyle(tester, field('Prep note').first);
      final nameStyle = fieldStyle(tester, field('Ingredient').first);
      expect(noteStyle.fontSize, lessThan(nameStyle.fontSize!));
      expect(noteStyle.color, cookdexColors.onSurfaceVariant);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('phone steps use a left drag gutter and an edited-field delete', (
    tester,
  ) async {
    final (c, _, _) = await controller();
    c.draft.steps.clear();
    c.draft.steps.addAll([EditableStep('Mix'), EditableStep('Bake')]);
    await editor(tester, c);
    final drag = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Reorder step 1',
    );
    await reveal(tester, drag);
    final text = find.byKey(ValueKey('${c.draft.steps.first.id}-text'));
    final textRect = tester.getRect(text);
    final dragRect = tester.getRect(drag);
    expect(find.byTooltip('Delete step 1'), findsNothing);
    expect(textRect.width, greaterThanOrEqualTo(298));
    expect(dragRect.width, 48);
    expect(dragRect.right, lessThan(textRect.left));
    await tester.tap(text);
    await tester.pumpAndSettle();
    final delete = find.byTooltip('Delete step 1');
    final editedRect = tester.getRect(text);
    final deleteRect = tester.getRect(delete);
    expect(deleteRect.width, 48);
    expect(deleteRect.right, editedRect.right);
    expect(deleteRect.bottom, editedRect.bottom);
    expect(deleteRect.left, greaterThan(editedRect.left));
    final firstRect = tester.getRect(
      find.byKey(ValueKey(c.draft.steps.first.id)),
    );
    final secondRect = tester.getRect(
      find.byKey(ValueKey(c.draft.steps.last.id)),
    );
    expect(secondRect.top - firstRect.bottom, 0);
    expect(secondRect.top - deleteRect.bottom, lessThanOrEqualTo(8));
    expect(firstRect.height, lessThanOrEqualTo(110));
    await tester.tap(find.byKey(ValueKey('${c.draft.steps.last.id}-text')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Delete step 1'), findsNothing);
    expect(find.byTooltip('Delete step 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final action in ['Cancel', 'Keep both', 'Replace']) {
    testWidgets('duplicate chooser distinguishes recipes and $action works', (
      tester,
    ) async {
      Recipe duplicate(
        String id,
        String description,
        String ingredient,
        String time,
      ) {
        final source = recipe(
          id,
          title: 'Same supper',
          description: description,
        );
        source.fields.ingredients[0] = Ingredient(
          amount: const Amount.toTaste(),
          unit: '',
          name: ingredient,
          prepNote: '',
          optional: false,
          section: '',
        );
        return Recipe(
          id: source.id,
          fields: source.fields,
          favorite: source.favorite,
          createdAt: source.createdAt,
          updatedAt: time,
          revision: source.revision,
        );
      }

      final repo = DuplicateEditorFake([
        duplicate(
          'first',
          'A supper with red lentils.',
          'red lentils',
          '2026-10-09T14:30:05Z',
        ),
        duplicate(
          'second',
          'A supper with garden carrots.',
          'garden carrots',
          '2026-10-09T14:30:35Z',
        ),
      ]);
      final store = RecipeStore(repo, LocalPreferences.memory());
      await store.initialize();
      final c = await EditorController.create(
        store: store,
        storage: MemoryDraftStorage(),
      );
      addTearDown(() {
        c.dispose();
        store.dispose();
      });
      c.draft.title = 'Same supper';
      c.draft.imported = true;
      await editor(tester, c, scale: 2, phoneFont: true);
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Recipe already exists'), findsOneWidget);
      expect(find.text('Recipe 1'), findsOneWidget);
      expect(find.text('Recipe 2'), findsOneWidget);
      expect(find.text('A supper with red lentils.'), findsOneWidget);
      expect(find.text('A supper with garden carrots.'), findsOneWidget);
      expect(find.text('Ingredients: red lentils'), findsOneWidget);
      expect(find.text('Ingredients: garden carrots'), findsOneWidget);
      expect(find.textContaining('2026-10-09T'), findsNothing);
      expect(find.textContaining(RegExp(r'^Updated .*:05$')), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Updated .*:35$')), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Replace'))
            .onPressed,
        isNull,
      );
      if (action == 'Replace') {
        await tester.ensureVisible(find.text('Recipe 2'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.text('Recipe 2'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Replace'))
              .onPressed,
          isNotNull,
        );
      }
      await tester.tap(find.widgetWithText(TextButton, action));
      await tester.pumpAndSettle();
      if (action == 'Cancel') {
        expect(repo.saves, 0);
        expect(repo.recipes, hasLength(2));
        expect(find.text('Review import'), findsOneWidget);
      } else {
        expect(repo.saves, 1);
        if (action == 'Replace') {
          expect(repo.choice, const DuplicateChoice.replace(id: 'second'));
          expect(repo.recipes, hasLength(2));
          expect(
            repo.recipes['first']!.fields.description,
            'A supper with red lentils.',
          );
        } else {
          expect(repo.choice, const DuplicateChoice.keepBoth());
          expect(repo.recipes, hasLength(3));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('delayed unit suggestions preserve focused input and selection', (
    tester,
  ) async {
    final source = recipe('unit-source');
    source.fields.ingredients
      ..clear()
      ..add(
        const Ingredient(
          amount: Amount.toTaste(),
          unit: 'ladle',
          name: 'stock',
          prepNote: '',
          optional: false,
          section: '',
        ),
      );
    final (c, repo, _) = await controller(recipes: [source]);
    final gate = Completer<Recipe?>();
    repo.detailGate = gate;
    await editor(tester, c);
    await reveal(tester, field('Unit').first);
    await tester.tap(field('Unit').first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final original = tester.widget<TextField>(field('Unit').first);
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'la',
        selection: TextSelection.collapsed(offset: 1),
      ),
    );
    await tester.pump();
    gate.complete(source);
    await tester.pumpAndSettle();
    final updated = tester.widget<TextField>(field('Unit').first);
    expect(updated.controller, same(original.controller));
    expect(updated.focusNode!.hasFocus, isTrue);
    expect(updated.controller!.selection.baseOffset, 1);
    await tester.tap(find.widgetWithText(ActionChip, 'ladle'));
    await tester.pumpAndSettle();
    expect(c.draft.sections.first.rows.first.unit, 'ladle');
    expect(updated.focusNode!.hasFocus, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'clearing a validation banner preserves field focus and selection',
    (tester) async {
      final (c, _, _) = await controller();
      c.draft.error = 'Give the recipe a title.';
      await editor(tester, c);
      final title = field('Title');
      await tester.tap(title);
      await tester.pump();
      final original = tester.widget<TextField>(title);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Soup',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 4),
        ),
      );
      await tester.pump();
      final updated = tester.widget<TextField>(title);
      expect(c.draft.error, isNull);
      expect(updated.controller, same(original.controller));
      expect(updated.focusNode, same(original.focusNode));
      expect(updated.focusNode!.hasFocus, isTrue);
      expect(updated.controller!.selection.baseOffset, 2);
      expect(
        updated.controller!.value.composing,
        const TextRange(start: 0, end: 4),
      );
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'empty grouped metadata hints wrap fully at largest system text',
    (tester) async {
      final (c, _, _) = await controller();
      await editor(tester, c, scale: 2, phoneFont: true);
      for (final label in ['Makes', 'Total time', 'Prep time', 'Cook time']) {
        await reveal(tester, field(label));
        final decoration = fieldDecoration(tester, field(label));
        expect(
          decoration.hintText,
          label == 'Makes' ? '4 servings or 12 tortillas' : null,
        );
        expect(decoration.floatingLabelBehavior, FloatingLabelBehavior.always);
        if (label == 'Makes') {
          final hint = find.descendant(
            of: field(label),
            matching: find.text('4 servings or 12 tortillas'),
          );
          final paragraph = tester.renderObject<RenderParagraph>(hint);
          expect(paragraph.didExceedMaxLines, isFalse);
        } else {
          expect(decoration.labelText, label);
        }
      }
      await reveal(tester, field('Makes'));
      expect(
        tester.getTopLeft(field('Makes')).dy,
        lessThan(tester.getTopLeft(field('Total time')).dy),
      );
      await reveal(tester, field('Prep time'));
      expect(
        tester.getTopLeft(field('Prep time')).dy,
        tester.getTopLeft(field('Cook time')).dy,
      );
      await reveal(tester, field('Total time'));
      await tester.tap(field('Total time'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Total time')).decoration!.labelText,
        'Total time',
      );
      await enterFieldText(tester, field('Total time'), '45 min');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Total time')).decoration!.labelText,
        'Total time',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets('long editor fields grow at 390dp / $scale text', (
      tester,
    ) async {
      final (c, _, _) = await controller();
      await editor(tester, c, scale: scale, phoneFont: true);
      final shortTitleHeight = tester.getSize(field('Title')).height;
      await enterFieldText(
        tester,
        field('Title'),
        'Grandma’s slow-simmered Sunday vegetable and country-style pork stew with garden herbs',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Title')).maxLines, isNull);
      expect(
        tester.getSize(field('Title')).height,
        greaterThan(shortTitleHeight),
      );
      await reveal(tester, field('Prep time'));
      final shortPrepHeight = tester.getSize(field('Prep time')).height;
      await enterFieldText(
        tester,
        field('Prep time'),
        '30 minutes, plus overnight chilling and resting before cooking',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(field('Prep time')).maxLines, 1);
      expect(tester.getSize(field('Prep time')).height, shortPrepHeight);
      expect(
        tester.getTopLeft(field('Prep time')).dy,
        tester.getTopLeft(field('Cook time')).dy,
      );
      await reveal(tester, field('Ingredient').first);
      final shortNameHeight = tester.getSize(field('Ingredient').first).height;
      await enterFieldText(
        tester,
        field('Ingredient').first,
        'boneless country-style pork shoulder with the fat trimmed and cut into generous pieces',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Ingredient').first).maxLines,
        isNull,
      );
      expect(
        tester.getSize(field('Ingredient').first).height,
        greaterThan(shortNameHeight),
      );
      final amount = tester.getRect(field('Amount').first);
      final ingredient = tester.getRect(field('Ingredient').first);
      if (scale == 1) {
        expect(amount.top, ingredient.top);
      } else {
        expect(ingredient.top, greaterThanOrEqualTo(amount.bottom));
        expect(ingredient.left, amount.left);
        expect(ingredient.right, lessThanOrEqualTo(390));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unnamed section options join Ingredients and can rename', (
    tester,
  ) async {
    final (c, _, _) = await controller();
    final section = c.draft.sections.single;
    await editor(tester, c, phoneFont: true);
    await reveal(tester, find.text('Ingredients'));
    final menu = find.byTooltip('Section 1 options');
    expect(menu, findsOneWidget);
    expect(find.byKey(ValueKey(section.id)), findsNothing);
    expect(
      tester.getRect(menu).center.dy,
      closeTo(tester.getRect(find.text('Ingredients')).center.dy, 1),
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await enterFieldText(tester, field('Name'), 'For the sauce');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(section.name, 'For the sauce');
    await reveal(tester, find.byKey(ValueKey(section.id)));
    expect(find.text('For the sauce'), findsOneWidget);
    expect(find.byTooltip('Section 1 options'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp large text editor and wide resize have no overflow', (
    tester,
  ) async {
    final (c, _, _) = await controller(base: recipe('original'));
    c.draft.sections.single.rows.single
      ..unit = 'clove'
      ..prepNote =
          'Finely chopped, with enough note text to grow onto more lines.'
      ..optional = true;
    await editor(tester, c, size: const Size(320, 780), scale: 1.5);
    await reveal(tester, field('Ingredient'));
    expect(tester.takeException(), isNull);
    await reveal(tester, field('Source link'));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
