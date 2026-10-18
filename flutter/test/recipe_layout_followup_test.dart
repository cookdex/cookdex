import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/recipe_metadata.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repository implements RecipeRepository {
  _Repository({this.mixed = false});
  final bool mixed;
  @override
  Future<CollectionSnapshot> snapshot() async => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: 0,
    summaries: List.generate(
      mixed ? 5 : 80,
      (index) => RecipeSummary(
        id: 'recipe-$index',
        title: index == 1
            ? 'A longer recipe title spanning several lines'
            : 'Recipe $index',
        description: index == 1
            ? 'A longer description using the available two lines of space.'
            : '',
        ingredients: const [],
        tags: mixed && (index == 1 || index == 4)
            ? const []
            : const ['dinner', 'quick'],
        notes: '',
        favorite: false,
        createdAt: '2026-01-01',
        updatedAt: '2026-01-01',
        revision: 1,
        servings: mixed && (index == 2 || index == 4)
            ? ''
            : mixed && index == 3
            ? '4 generous bowls with bread and vegetables'
            : '4 bowls',
        prepTime: '',
        cookTime: '',
        totalTime: mixed && (index == 2 || index == 4)
            ? ''
            : mixed && index == 3
            ? '30 min, plus chilling and resting overnight'
            : '30 min',
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

Future<LocalPreferences> _screen(
  WidgetTester tester,
  double width, {
  double scale = 1,
  bool mixed = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final preferences = LocalPreferences.memory();
  final store = RecipeStore(_Repository(mixed: mixed), preferences);
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
  return preferences;
}

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('mixed footers share metadata and tag slots at scale $scale', (
      tester,
    ) async {
      final preferences = await _screen(
        tester,
        1800,
        scale: scale,
        mixed: true,
      );
      final cards = [
        for (var i = 0; i < 5; i++) find.byKey(ValueKey('recipe-$i')),
      ];
      Rect metadata(int index) => tester.getRect(
        find.descendant(
          of: cards[index],
          matching: find.byType(RecipeMetadata),
        ),
      );
      Rect tags(int index) => tester.getRect(
        find.descendant(of: cards[index], matching: find.byType(RecipeTagLine)),
      );
      final first = tester.getRect(cards.first);
      for (final card in cards.skip(1)) {
        expect(tester.getRect(card).height, first.height);
      }
      expect(metadata(0).top, closeTo(metadata(1).top, 0.01));
      expect(metadata(0).top, closeTo(metadata(3).top, 0.01));
      expect(metadata(3).height, metadata(0).height);
      expect(tags(0).top, closeTo(tags(2).top, 0.01));
      expect(tags(0).top, closeTo(tags(3).top, 0.01));
      expect(tags(0).top, closeTo(metadata(3).bottom + 8, 0.01));
      expect(tags(0).bottom, closeTo(first.bottom - 10, 0.01));
      expect(tags(1).height, tags(0).height);
      expect(metadata(2).height, metadata(0).height);
      expect(tags(4).height, tags(0).height);
      // Filtering preserves the grid's shared extent, including empty slots.
      preferences.setQuery('Recipe 0');
      await tester.pumpAndSettle();
      expect(tester.getRect(cards.first).height, first.height);
      expect(tags(0).top, closeTo(metadata(0).bottom + 8, 0.01));
      expect(tester.takeException(), isNull);
    });
  }
  for (final scale in [1.0, 2.0]) {
    testWidgets('card details align at the bottom at text scale $scale', (
      tester,
    ) async {
      await _screen(tester, 800, scale: scale);
      final first = find.byKey(const ValueKey('recipe-0'));
      final second = find.byKey(const ValueKey('recipe-1'));
      final firstCard = tester.getRect(first);
      final secondCard = tester.getRect(second);
      expect(firstCard.height, secondCard.height);
      final metadata = <Rect>[
        for (final card in [first, second])
          tester.getRect(
            find.descendant(of: card, matching: find.byType(RecipeMetadata)),
          ),
      ];
      final tags = <Rect>[
        for (final card in [first, second])
          tester.getRect(
            find.descendant(of: card, matching: find.byType(RecipeTagLine)),
          ),
      ];
      expect(metadata[0].top, closeTo(metadata[1].top, 0.01));
      expect(tags[0].bottom, closeTo(tags[1].bottom, 0.01));
      expect(firstCard.bottom - tags[0].bottom, closeTo(10, 0.01));
      final title = tester.getRect(find.text('Recipe 0'));
      expect(metadata[0].top - title.bottom, greaterThan(8));
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [600.0, 800.0, 1280.0, 1920.0]) {
    testWidgets('search and all controls share a pinned row at $width dp', (
      tester,
    ) async {
      await _screen(tester, width);
      final search = tester.getRect(find.byKey(const Key('recipe-search')));
      expect(search.width, lessThanOrEqualTo(560));
      for (final control in [
        find.widgetWithText(FilterChip, 'Favorites'),
        find.widgetWithText(ActionChip, 'Recently edited'),
        find.byKey(const Key('recipe-view')),
      ]) {
        final rect = tester.getRect(control);
        expect(rect.center.dy, closeTo(search.center.dy, 0.01));
        expect(rect.left, greaterThan(search.right));
        if (width >= 800) {
          expect(rect.right, lessThanOrEqualTo(width - 16));
        }
      }
      await tester.drag(
        find.byWidgetPredicate((w) => w is CustomScrollView),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      final pinned = tester.getRect(find.byKey(const Key('recipe-search')));
      expect(pinned.top, lessThan(search.top));
      await tester.drag(
        find.byWidgetPredicate((w) => w is CustomScrollView),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('recipe-search'))).top,
        closeTo(pinned.top, 0.01),
      );
      expect(
        tester.getRect(find.widgetWithText(FilterChip, 'Favorites')).center.dy,
        closeTo(pinned.center.dy, 0.01),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('compact phone retains search above the controls', (
    tester,
  ) async {
    await _screen(tester, 390);
    final search = tester.getRect(find.byKey(const Key('recipe-search')));
    final favorites = tester.getRect(
      find.widgetWithText(FilterChip, 'Favorites'),
    );
    expect(favorites.top, greaterThanOrEqualTo(search.bottom));
    expect(find.byKey(const Key('wide-recipe-toolbar')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text wide controls remain reachable and menus work', (
    tester,
  ) async {
    final preferences = await _screen(tester, 600, scale: 2);
    final toolbar = find.byKey(const Key('wide-recipe-toolbar'));
    final scroll = find.descendant(
      of: toolbar,
      matching: find.byWidgetPredicate((w) => w is SingleChildScrollView),
    );
    await tester.drag(scroll, const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recipe-view')));
    await tester.pumpAndSettle();
    expect(preferences.view, RecipeView.compact);
    expect(tester.takeException(), isNull);
  });
}
