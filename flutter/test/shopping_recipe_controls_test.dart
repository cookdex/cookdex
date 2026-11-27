import 'dart:async';

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipes_on_list_screen.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'recipe_store_test.dart' show recipe;
import 'shopping_screen_test.dart'
    show ShoppingFake, FakeShoppingUndo, item, screen, menu;

Recipe shoppingControlRecipe(String id, String title, List<String> names) {
  final base = recipe(id, title: title);
  return Recipe(
    id: id,
    fields: RecipeFields(
      title: title,
      description: '',
      servings: '4',
      prepTime: '',
      cookTime: '',
      totalTime: '',
      source: '',
      tags: const [],
      notes: '',
      steps: const ['Mix.'],
      ingredients: [
        for (final (i, name) in names.indexed)
          Ingredient(
            amount: Amount.rational(
              numerator: name == 'Carrots' || name == 'Olive oil' ? 2 : 1,
              denominator: name == 'Salt' || name == 'Black pepper' ? 2 : 1,
            ),
            unit: name == 'Green lentils'
                ? 'cup'
                : name == 'Olive oil'
                ? 'tbsp'
                : name == 'Carrots' || name == 'Leeks'
                ? ''
                : 'tsp',
            name: name,
            prepNote: '',
            optional: false,
            section: i < 2 ? 'For the bowl' : 'To finish',
          ),
      ],
    ),
    favorite: false,
    createdAt: base.createdAt,
    updatedAt: base.updatedAt,
    revision: base.revision,
  );
}

List<ShoppingRemovalLine> shoppingRemovalFixture() => [
  const ShoppingRemovalLine(
    id: 'lemon',
    name: 'Lemon',
    before: '1',
    after: null,
    action: 'remove',
    reason: '',
  ),
  const ShoppingRemovalLine(
    id: 'lentils',
    name: 'Green lentils',
    before: '3 cups',
    after: '1 cup',
    action: 'reduce',
    reason: '',
  ),
  const ShoppingRemovalLine(
    id: 'carrots',
    name: 'Carrots',
    before: '2',
    after: '2',
    action: 'keep',
    reason: 'Already checked off',
  ),
  const ShoppingRemovalLine(
    id: 'yogurt',
    name: 'Greek yogurt',
    before: '1 tub',
    after: '1 tub',
    action: 'keep',
    reason: 'Changed by hand',
  ),
  const ShoppingRemovalLine(
    id: 'parsley',
    name: 'Flat-leaf parsley',
    before: '1 bunch',
    after: '1 bunch',
    action: 'keep',
    reason: 'Added before this update',
  ),
  const ShoppingRemovalLine(
    id: 'bread',
    name: 'Crusty bread',
    before: '1 loaf',
    after: '1 loaf',
    action: 'keep',
    reason: 'A contributing recipe was deleted',
  ),
];

class RecipeRemovalFake extends ShoppingFake
    implements ShoppingRemovalRepository {
  RecipeRemovalFake()
    : super(
        [
          shoppingControlRecipe('bowl', 'Lemon lentil bowl', [
            'Green lentils',
            'Carrots',
            'Olive oil',
            'Salt',
          ]),
          shoppingControlRecipe('soup', 'Garden soup', [
            'Green lentils',
            'Leeks',
            'Black pepper',
          ]),
        ],
        [
          item('lemon', 'Lemon', quantity: '1', sources: ['bowl']),
          item(
            'lentils',
            'Green lentils',
            quantity: '3 cups',
            sources: ['bowl', 'soup'],
          ),
          item(
            'carrots',
            'Carrots',
            quantity: '2',
            sources: ['bowl'],
            checked: true,
          ),
          item('soap', 'Dish soap'),
          item('yogurt', 'Greek yogurt', quantity: '1 tub'),
          item(
            'parsley',
            'Flat-leaf parsley',
            quantity: '1 bunch',
            sources: ['bowl'],
          ),
          item(
            'bread',
            'Crusty bread',
            quantity: '1 loaf',
            sources: ['bowl', 'deleted'],
          ),
        ],
      );

  int previewCalls = 0, removalCalls = 0;
  bool listFails = false, previewFails = false, removalFails = false;
  Completer<void>? previewGate;
  List<ShoppingRemovalLine> lines = shoppingRemovalFixture();
  String? failAddFor;
  final addedSelections = <(String, List<int>)>[];

  bool _belongsTo(ShoppingItem row, String recipeId) =>
      row.contributorIds.contains(recipeId) ||
      // Editing detaches visible sources but retains the removal association.
      (row.id == 'yogurt' && recipeId == 'bowl');

  List<ShoppingRemovalLine> _previewLines(String recipeId) => [
    for (final line in lines)
      if (items.any((row) => row.id == line.id && _belongsTo(row, recipeId)))
        line,
  ];

  @override
  Future<List<String>> ingredientAmounts(
    List<Ingredient> ingredients,
  ) async => [
    for (final ingredient in ingredients)
      if (ingredient.name == 'Salt' || ingredient.name == 'Black pepper')
        '1/2'
      else if (ingredient.name == 'Carrots' || ingredient.name == 'Olive oil')
        '2'
      else
        '1',
  ];

  @override
  Future<ShoppingResult> addShopping(
    int generation,
    String id,
    List<int> indices,
  ) async {
    if (id == failAddFor) {
      throw const ServiceError(
        code: ErrorCode.storage,
        message: 'Could not add this recipe.',
      );
    }
    final result = await super.addShopping(generation, id, indices);
    addedSelections.add((id, [...indices]));
    return result;
  }

  @override
  Future<List<ShoppingRecipe>> shoppingRecipes(int generation) async {
    if (listFails) {
      throw const ServiceError(
        code: ErrorCode.storage,
        message: 'Could not read the list.',
      );
    }
    return [
      for (final recipe in recipes.values)
        if (_previewLines(recipe.id).any((line) => line.action != 'keep'))
          ShoppingRecipe(
            recipeId: recipe.id,
            title: recipe.fields.title,
            itemCount: _previewLines(recipe.id)
                .where((line) => line.action != 'keep')
                .length,
          ),
    ];
  }

  @override
  Future<ShoppingRemovalPreview> previewShoppingRemoval(
    int generation,
    String recipeId,
  ) async {
    previewCalls++;
    if (previewGate != null) await previewGate!.future;
    if (previewFails) {
      throw const ServiceError(
        code: ErrorCode.storage,
        message: 'Could not read recipe shares.',
      );
    }
    return ShoppingRemovalPreview(
      generation: this.generation,
      recipeId: recipeId,
      title: recipes[recipeId]!.fields.title,
      lines: _previewLines(recipeId),
    );
  }

  @override
  Future<ShoppingResult> removeShoppingRecipe(
    int generation,
    String recipeId,
  ) async {
    removalCalls++;
    if (generation != this.generation) {
      throw const ServiceError(
        code: ErrorCode.staleWrite,
        message: 'Shopping list changed.',
      );
    }
    if (removalFails) {
      throw const ServiceError(
        code: ErrorCode.storage,
        message: 'Could not write the list.',
      );
    }
    final before = [...items];
    final changes = {for (final line in _previewLines(recipeId)) line.id: line};
    items = [
      for (final row in items)
        if (changes[row.id]?.action != 'remove')
          if (changes[row.id]?.action == 'reduce')
            item(
              row.id,
              row.name,
              quantity: changes[row.id]!.after ?? '',
              sources: row.contributorIds
                  .where((id) => id != recipeId)
                  .toList(),
            )
          else
            row,
    ];
    this.generation++;
    return ShoppingResult(
      snapshot: current,
      undo: FakeShoppingUndo(before, [...items]),
    );
  }
}

Future<(RecipeStore, RecipeRemovalFake)> shoppingControlStore() async {
  final repository = RecipeRemovalFake();
  final preferences = LocalPreferences.memory();
  preferences.setStaples(['Salt', 'Olive oil', 'Pepper']);
  final store = RecipeStore(repository, preferences);
  await store.initialize();
  addTearDown(() {
    store.dispose();
    preferences.dispose();
  });
  return (store, repository);
}

Future<void> shoppingPicker(
  WidgetTester tester,
  RecipeStore store,
  List<Recipe> recipes, {
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => recipes.length == 1
                ? showShoppingSelection(context, store, recipes.single)
                : showBatchShoppingSelection(context, store, recipes),
            child: const Text('Choose ingredients'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Choose ingredients'));
  await tester.pumpAndSettle();
}

CheckboxListTile selection(WidgetTester tester, int index) =>
    tester.widget<CheckboxListTile>(
      find.byKey(ValueKey('shopping-selection-$index')),
    );

void main() {
  for (final batch in [false, true]) {
    testWidgets('everyday staples apply in ${batch ? "batch" : "single"} picker', (
      tester,
    ) async {
      final (store, _) = await shoppingControlStore();
      store.preferences.setStaples(['rice', 'flour', 'sugar', 'salt', 'pepper']);
      final names = [
        'steamed rice', 'all-purpose flour', 'granulated sugar',
        'salt and pepper', 'rice vinegar',
      ];
      final recipes = [
        shoppingControlRecipe('everyday', 'Everyday bowl', names),
        if (batch) shoppingControlRecipe('another', 'Another bowl', ['brown sugar']),
      ];
      await shoppingPicker(tester, store, recipes);
      for (var i = 0; i < names.length; i++) {
        await tester.ensureVisible(find.byKey(ValueKey('shopping-selection-$i')));
        expect(selection(tester, i).value, i == 4, reason: names[i]);
      }
      if (batch) {
        await tester.ensureVisible(
          find.byKey(const ValueKey('shopping-selection-5')),
        );
        expect(selection(tester, 5).value, isTrue);
      }
    });
  }

  testWidgets(
    'staple picker preserves positions and permits explicit inclusion',
    (tester) async {
      final (store, repository) = await shoppingControlStore();
      await shoppingPicker(tester, store, [repository.recipes['bowl']!]);
      expect(selection(tester, 0).value, isTrue);
      expect(selection(tester, 1).value, isTrue);
      expect(selection(tester, 2).value, isFalse);
      expect(selection(tester, 3).value, isFalse);
      expect(
        find.textContaining('Staple', findRichText: true),
        findsNWidgets(2),
      );
      await tester.tap(find.text('Olive oil'));
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(repository.selected, [0, 1, 2]);
      expect(find.text('Added to shopping list'), findsOneWidget);
    },
  );

  testWidgets(
    'batch picker defaults each recipe and keeps selection controls',
    (tester) async {
      final (store, repository) = await shoppingControlStore();
      await shoppingPicker(
        tester,
        store,
        repository.recipes.values.toList(),
        size: const Size(390, 844),
        scale: 1.5,
      );
      expect(find.text('Lemon lentil bowl'), findsOneWidget);
      await tester.ensureVisible(find.text('Black pepper'));
      expect(selection(tester, 6).value, isFalse);
      await tester.tap(find.text('Select all'));
      await tester.pump();
      expect(selection(tester, 6).value, isTrue);
      await tester.tap(find.text('Select none'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Add'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'batch retries only recipes still pending after a write failure',
    (tester) async {
      final (store, repository) = await shoppingControlStore();
      repository.failAddFor = 'soup';
      await shoppingPicker(tester, store, repository.recipes.values.toList());
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(repository.addedSelections.length, 1);
      expect(repository.addedSelections.single.$1, 'bowl');
      expect(find.text('Could not add this recipe.'), findsOneWidget);
      expect(selection(tester, 0).onChanged, isNull);
      repository.failAddFor = null;
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      expect(repository.addedSelections.map((entry) => entry.$1), [
        'bowl',
        'soup',
      ]);
      expect(repository.addedSelections.last.$2, [0, 1]);
    },
  );

  testWidgets(
    'sheet preview Back and removal return to Shopping with named Undo',
    (tester) async {
      final (store, repository) = await shoppingControlStore();
      await screen(tester, store);
      await menu(tester, 'Recipes on this list');
      expect(find.byType(RecipesOnListSheet), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(RecipesOnListSheet),
          matching: find.text('2 items'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('shopping-recipe-bowl')));
      await tester.pumpAndSettle();
      expect(repository.removalCalls, 0);
      expect(find.byType(RecipesOnListSheet), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('shopping-removal-preview')),
          matching: find.text('Lemon lentil bowl'),
        ),
        findsOneWidget,
      );
      expect(find.text('Comes off'), findsOneWidget);
      expect(find.text('Gets smaller'), findsOneWidget);
      expect(find.text('Stays'), findsOneWidget);
      final reduction = tester.widget<Text>(
        find.byKey(const ValueKey('shopping-removal-label-lentils')),
      );
      expect(
        reduction.textSpan!.toPlainText(includeSemanticsLabels: false),
        endsWith(' Green lentils'),
      );
      expect(
        find.textContaining('Dish soap', findRichText: true),
        findsNothing,
      );
      expect(find.text('Cancel'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('A contributing recipe was deleted'),
        250,
        scrollable: find.descendant(
          of: find.byKey(const Key('shopping-removal-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      for (final reason
          in shoppingRemovalFixture()
              .where((line) => line.action == 'keep')
              .map((line) => line.reason)) {
        expect(find.text(reason), findsOneWidget);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(repository.removalCalls, 0);
      expect(find.byType(RecipesOnListSheet), findsNothing);
      expect(find.byTooltip('Shopping list options'), findsOneWidget);
      await menu(tester, 'Recipes on this list');
      await tester.tap(find.byKey(const ValueKey('shopping-recipe-bowl')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('confirm-shopping-recipe-removal')),
      );
      await tester.pumpAndSettle();
      expect(repository.removalCalls, 1);
      expect(find.byType(RecipesOnListSheet), findsNothing);
      expect(find.byKey(const Key('shopping-removal-scroll')), findsNothing);
      expect(find.byTooltip('Shopping list options'), findsOneWidget);
      expect(find.text('Lemon lentil bowl removed from list'), findsOneWidget);
      expect(store.shopping.any((row) => row.id == 'lemon'), isFalse);
      expect(
        store.shopping.singleWhere((row) => row.id == 'lentils').quantityText,
        '1 cup',
      );
      expect(find.text('Undo'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(
        store.shopping.singleWhere((row) => row.id == 'lentils').quantityText,
        '3 cups',
      );
      expect(store.shopping.any((row) => row.id == 'lemon'), isTrue);
    },
  );

  testWidgets('stale preview requires a fresh preview before a removal retry', (
    tester,
  ) async {
    final (store, repository) = await shoppingControlStore();
    await screen(tester, store, size: const Size(320, 780), scale: 2);
    await menu(tester, 'Recipes on this list');
    await tester.tap(find.byKey(const ValueKey('shopping-recipe-bowl')));
    await tester.pumpAndSettle();
    repository.generation++;
    await tester.tap(find.byKey(const Key('confirm-shopping-recipe-removal')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Your shopping list changed. Refresh the preview before removing items.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-shopping-recipe-removal')),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Refresh preview'));
    await tester.tap(find.text('Refresh preview'));
    await tester.pumpAndSettle();
    expect(repository.previewCalls, 2);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-shopping-recipe-removal')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('150 percent reduction keeps both amounts and icon on one line', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final (store, repository) = await shoppingControlStore();
      await screen(tester, store, scale: 1.5);
      await menu(tester, 'Recipes on this list');
      await tester.tap(find.byKey(const ValueKey('shopping-recipe-bowl')));
      await tester.pumpAndSettle();
      final amounts = find.byKey(
        const ValueKey('shopping-removal-amounts-lentils'),
      );
      final before = find.descendant(
        of: amounts,
        matching: find.text('3 cups'),
      );
      final after = find.descendant(of: amounts, matching: find.text('1 cup'));
      final arrow = find.descendant(
        of: amounts,
        matching: find.byIcon(Symbols.arrow_right_alt),
      );
      expect(before, findsOneWidget);
      expect(after, findsOneWidget);
      expect(arrow, findsOneWidget);
      final beforeRect = tester.getRect(before);
      final afterRect = tester.getRect(after);
      final arrowRect = tester.getRect(arrow);
      final groupRect = tester.getRect(amounts);
      final labelRect = tester.getRect(
        find.byKey(const ValueKey('shopping-removal-label-lentils')),
      );
      expect(beforeRect.top, closeTo(afterRect.top, .01));
      expect(beforeRect.bottom, closeTo(afterRect.bottom, .01));
      expect(arrowRect.left, greaterThanOrEqualTo(beforeRect.right));
      expect(arrowRect.right, lessThanOrEqualTo(afterRect.left));
      expect(groupRect.height, closeTo(beforeRect.height, .01));
      final amountStyle = tester.widget<Text>(before).style!;
      expect(
        beforeRect.height,
        closeTo(amountStyle.fontSize! * amountStyle.height! * 1.5, .1),
      );
      expect(groupRect.left, greaterThanOrEqualTo(labelRect.left));
      expect(groupRect.right, lessThanOrEqualTo(labelRect.right + .1));
      expect(
        tester
            .getSemantics(amounts)
            .label
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
        '3 cups to 1 cup Green lentils',
      );
      expect(tester.takeException(), isNull);

      // Exact mixed measures can be longer than the phone's available line.
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      repository.lines = [
        for (final line in repository.lines)
          if (line.id == 'lentils')
            const ShoppingRemovalLine(
              id: 'lentils',
              name: 'Green lentils',
              before: '1 1/2 cups + 3 tbsp + 1 tsp',
              after: '3/4 cup + 1 tbsp + 1 tsp',
              action: 'reduce',
              reason: '',
            )
          else
            line,
      ];
      await menu(tester, 'Recipes on this list');
      await tester.tap(find.byKey(const ValueKey('shopping-recipe-bowl')));
      await tester.pumpAndSettle();
      final mixedRect = tester.getRect(amounts);
      final mixedLabelRect = tester.getRect(
        find.byKey(const ValueKey('shopping-removal-label-lentils')),
      );
      expect(mixedRect.left, greaterThanOrEqualTo(mixedLabelRect.left));
      expect(mixedRect.right, lessThanOrEqualTo(mixedLabelRect.right + .1));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('empty removal sheet explains protected-only shopping items', (
    tester,
  ) async {
    final (store, repository) = await shoppingControlStore();
    repository.lines = repository.lines
        .where((line) => line.action == 'keep')
        .toList();
    await screen(tester, store);
    await menu(tester, 'Recipes on this list');
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.text(
        'Nothing to remove. Checked, edited and older items stay on your list.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('shopping-recipe-bowl')), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(repository.previewCalls, 0);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Shopping list options'), findsOneWidget);
    expect(repository.removalCalls, 0);
  });

  testWidgets('Shopping menu groups recipe and list actions in reading order', (
    tester,
  ) async {
    final (store, _) = await shoppingControlStore();
    await screen(tester, store);
    await tester.tap(find.byTooltip('Shopping list options'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
          .map((item) => item.value),
      [
        'recipes',
        'staples',
        'categories',
        'check',
        'uncheck',
        'checked',
        'save',
        'clear',
      ],
    );
    expect(find.byType(PopupMenuDivider), findsNWidgets(4));
  });

  testWidgets('preview loading failure and keep-only result cannot remove', (
    tester,
  ) async {
    final (store, repository) = await shoppingControlStore();
    repository.previewGate = Completer<void>();
    await screen(tester, store);
    await menu(tester, 'Recipes on this list');
    await tester.tap(find.byKey(const ValueKey('shopping-recipe-bowl')));
    await tester.pump();
    // Finish the page transition while the repository gate keeps loading open.
    // pumpAndSettle cannot settle an indeterminate progress indicator.
    await tester.pump(const Duration(milliseconds: 600));
    expect(repository.previewCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.previewFails = true;
    repository.previewGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Could not read recipe shares.'), findsOneWidget);
    repository.previewFails = false;
    repository.lines = shoppingRemovalFixture()
        .where((line) => line.action == 'keep')
        .toList();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No items can be removed.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-shopping-recipe-removal')),
          )
          .onPressed,
      isNull,
    );
    expect(repository.removalCalls, 0);
  });
}
