import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements RecipeRepository {
  @override
  Future<CollectionSnapshot> snapshot() async => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: 0,
    summaries: List.generate(
      8,
      (index) => RecipeSummary(
        id: 'recipe-$index',
        title: index == 1
            ? 'A considerably longer recipe title that needs several lines to read'
            : 'Recipe $index',
        description: index == 1
            ? 'A description that uses the available two lines of card space.'
            : '',
        ingredients: const [],
        tags: index == 0
            ? const [
                'dinner',
                'quick',
                'vegetarian',
                'soup',
                'garden vegetables',
              ]
            : const [],
        notes: '',
        favorite: false,
        createdAt: '2026-01-01',
        updatedAt: '2026-01-01',
        revision: 1,
        servings: '4 bowls',
        prepTime: 'about 10 min',
        cookTime: '20–25 min',
        totalTime: '',
      ),
    ),
    shopping: const [],
    conflicts: const [],
    hasPrevious: false,
  );

  @override
  Stream<CollectionEvent> subscribe() => const Stream.empty();
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _screen(
  WidgetTester tester,
  double width,
  RecipeView view, {
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final preferences = LocalPreferences.memory()..view = view;
  final store = RecipeStore(_Repository(), preferences);
  await store.refresh();
  addTearDown(store.dispose);
  addTearDown(preferences.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: RecipesScreen(
          store: store,
          preferences: preferences,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final title in [
    'Soup',
    'A long recipe title that needs at least two lines in this narrow card',
  ]) {
    testWidgets('three-line budget for $title', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 220,
              child: RecipeCardTextBudget(
                title: title,
                description: 'A detailed recipe description with enough words to fill all the available lines.',
              ),
            ),
          ),
        ),
      );
      final titleWidget = tester.widget<Text>(find.text(title));
      final description = tester.widget<Text>(
        find.textContaining('A detailed recipe'),
      );
      expect(titleWidget.maxLines, 2);
      expect(description.maxLines, title == 'Soup' ? 2 : 1);
      expect(description.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });
  }
  for (final view in RecipeView.values) {
    for (final entry in <double, int>{
      390: 1,
      800: 2,
      1280: 3,
      1800: 5,
    }.entries) {
      testWidgets(
        '${view.name} adds ${entry.value} columns at ${entry.key}dp',
        (tester) async {
          await _screen(tester, entry.key, view);
          final first = tester.getRect(find.byKey(const ValueKey('recipe-0')));
          expect(first.width, inInclusiveRange(320, 420));
          for (var i = 1; i < entry.value; i++) {
            final next = tester.getRect(find.byKey(ValueKey('recipe-$i')));
            expect(next.top, first.top);
            expect(next.height, first.height);
            expect(next.width, first.width);
            expect(next.left, greaterThan(first.left));
          }
          final following = tester.getRect(
            find.byKey(ValueKey('recipe-${entry.value}')),
          );
          expect(following.top, greaterThan(first.top));
          if (view == RecipeView.cards && entry.value > 1) {
            expect(following.height, first.height);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('cards keep prep and cook labels when total is absent', (
    tester,
  ) async {
    await _screen(tester, 800, RecipeView.cards);
    expect(find.text('Prep about 10 min'), findsWidgets);
    expect(find.text('Cook 20–25 min'), findsWidgets);
    expect(find.textContaining('+'), findsWidgets);
  });

  testWidgets('single-line tags fit at large text and expose every tag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const Center(
              child: SizedBox(
                width: 250,
                child: RecipeTagLine([
                  'Dinner',
                  'quick',
                  'vegetarian',
                  'garden vegetables',
                ]),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('+3'), findsOneWidget);
    expect(
      tester.getRect(find.text('+3')).top,
      tester.getRect(find.text('Dinner')).top,
    );
    expect(
      find.byTooltip('Dinner, quick, vegetarian, garden vegetables'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text cards remain equal height without overflow', (
    tester,
  ) async {
    await _screen(tester, 1280, RecipeView.cards, scale: 2);
    expect(
      tester.getSize(find.byKey(const ValueKey('recipe-0'))).height,
      tester.getSize(find.byKey(const ValueKey('recipe-1'))).height,
    );
    expect(tester.takeException(), isNull);
  });
}
