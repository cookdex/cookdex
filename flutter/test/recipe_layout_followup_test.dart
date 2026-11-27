import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/recipe_metadata.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;

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
  double height = 1000,
  TargetPlatform platform = TargetPlatform.android,
  ScrollController? controller,
  RecipeView view = RecipeView.cards,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final preferences = LocalPreferences.memory()..view = view;
  final store = RecipeStore(_Repository(mixed: mixed), preferences);
  await store.refresh();
  addTearDown(store.dispose);
  addTearDown(preferences.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme().copyWith(platform: platform),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: RecipesScreen(
          store: store,
          preferences: preferences,
          controller: controller,
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
  for (final (name, size, platform, centered) in [
    ('phone', const Size(390, 844), TargetPlatform.android, false),
    ('landscape phone', const Size(1000, 500), TargetPlatform.android, false),
    ('portrait tablet', const Size(800, 1280), TargetPlatform.android, false),
    (
      'wide portrait tablet',
      const Size(1000, 1400),
      TargetPlatform.android,
      false,
    ),
    ('landscape tablet', const Size(1280, 800), TargetPlatform.android, true),
    ('Windows', const Size(1800, 1000), TargetPlatform.windows, true),
  ]) {
    testWidgets('$name keeps the same header in Cards and Compact', (
      tester,
    ) async {
      final preferences = await _screen(
        tester,
        size.width,
        height: size.height,
        platform: platform,
      );
      final brand = find.byKey(const Key('recipe-library-brand'));
      final search = find.byKey(const Key('recipe-search'));
      final toolbar = find.byKey(const Key('wide-recipe-toolbar'));
      final header = [
        brand,
        search,
        find.widgetWithText(FilterChip, 'Favorites'),
        find.byWidgetPredicate(
          (widget) => widget is ActionChip && widget.tooltip == 'Sort recipes',
        ),
        find.byKey(const Key('recipe-view')),
      ];
      final cardsHeader = header.map(tester.getRect).toList();
      expect(tester.getRect(brand).left, tester.getRect(search).left);
      if (centered) {
        expect(tester.getRect(toolbar).width, recipeContentMaxWidth);
        expect(tester.getRect(toolbar).center.dx, size.width / 2);
      } else {
        expect(tester.getRect(brand).left, 16);
        if (size.width >= 600) {
          expect(tester.getRect(toolbar).width, size.width - 32);
        }
      }
      preferences.setView(RecipeView.compact);
      await tester.pumpAndSettle();
      expect(header.map(tester.getRect).toList(), cardsHeader);
      if (centered) {
        final row = tester.getRect(find.byKey(const ValueKey('recipe-0')));
        expect(row.left, tester.getRect(toolbar).left);
        expect(row.right, tester.getRect(toolbar).right);
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'all phone controls stay visible at $width dp / $scale text',
        (tester) async {
          await loadSectionCaptureFonts(tester);
          final preferences = await _screen(tester, width, scale: scale);
          final controls = [
            find.widgetWithText(FilterChip, 'Favorites'),
            // Tooltip wraps the painted body inside the chip's padded target.
            find.byWidgetPredicate(
              (widget) =>
                  widget is ActionChip && widget.tooltip == 'Sort recipes',
            ),
            find.byKey(const Key('recipe-view')),
          ];
          final initial = controls.map(tester.getRect).toList();
          final brand = tester.getRect(
            find.byKey(const Key('recipe-library-brand')),
          );
          final search = tester.getRect(find.byKey(const Key('recipe-search')));
          final view = initial.last;
          if (width == 320 || scale > 1) {
            expect(view.center.dy, closeTo(brand.center.dy, .01));
            expect(view.left, greaterThanOrEqualTo(brand.right));
            expect(view.bottom, lessThanOrEqualTo(search.top));
          } else {
            expect(view.center.dy, closeTo(initial.first.center.dy, .01));
            expect(view.top, greaterThanOrEqualTo(search.bottom));
          }
          for (final selectedView in RecipeView.values) {
            preferences.setView(selectedView);
            for (final favorites in [false, true]) {
              preferences.setFavoritesOnly(favorites);
              await tester.pumpAndSettle();
              expect(controls.map(tester.getRect).toList(), initial);
              for (final control in controls) {
                final rect = tester.getRect(control);
                expect(rect.left, greaterThanOrEqualTo(16));
                expect(rect.right, lessThanOrEqualTo(width - 16));
                expect(rect.height, greaterThanOrEqualTo(48));
                expect(control.hitTestable(), findsOneWidget);
              }
            }
          }
          await tester.tap(controls.last);
          await tester.pumpAndSettle();
          expect(preferences.view, RecipeView.cards);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

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
        expect(tester.getRect(card).height, closeTo(first.height, 1e-6));
      }
      expect(metadata(0).top, closeTo(metadata(1).top, 0.01));
      expect(metadata(0).top, closeTo(metadata(2).top, 0.01));
      expect(metadata(3).height, closeTo(metadata(0).height, 1e-6));
      expect(tags(0).top, closeTo(tags(2).top, 0.01));
      expect(tags(3).top, closeTo(tags(4).top, 0.01));
      expect(tags(0).top, closeTo(metadata(2).bottom + 8, 0.01));
      expect(tags(3).top, closeTo(metadata(3).bottom + 8, 0.01));
      expect(tags(0).bottom, closeTo(first.bottom - 10, 0.01));
      expect(tags(1).height, closeTo(tags(0).height, 1e-6));
      expect(metadata(2).height, closeTo(metadata(0).height, 1e-6));
      expect(tags(4).height, closeTo(tags(0).height, 1e-6));
      // Filtering preserves the grid's shared extent, including empty slots.
      preferences.setQuery('Recipe 0');
      await tester.pumpAndSettle();
      expect(tester.getRect(cards.first).height, closeTo(first.height, 1e-6));
      expect(tags(0).top, closeTo(metadata(0).bottom + 8, 0.01));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size, platform) in [
    ('Windows', const Size(1800, 1000), TargetPlatform.windows),
    ('landscape tablet', const Size(1280, 800), TargetPlatform.android),
    ('wide portrait tablet', const Size(1000, 1400), TargetPlatform.android),
  ]) {
    for (final view in RecipeView.values) {
      testWidgets('$name ${view.name} scrolls from both empty side margins', (
        tester,
      ) async {
        final controller = ScrollController();
        addTearDown(controller.dispose);
        final preferences = await _screen(
          tester,
          size.width,
          height: size.height,
          platform: platform,
          controller: controller,
          view: view,
        );
        final scroll = find.byKey(const PageStorageKey('recipes-scroll'));
        final viewport = tester.getRect(scroll);
        final first = tester.getRect(find.byKey(const ValueKey('recipe-0')));
        expect(viewport.width, size.width);
        // The hit point sits outside every card/row, inside the actual viewport.
        final margin = first.left / 2;
        expect(margin, greaterThan(0));
        expect(find.byKey(const ValueKey('recipe-79')), findsNothing);
        for (final x in [margin, size.width - margin]) {
          controller.jumpTo(0);
          await tester.pumpAndSettle();
          final start = Offset(x, viewport.center.dy + 100);
          await tester.dragFrom(start, const Offset(0, -220));
          await tester.pumpAndSettle();
          expect(controller.offset, greaterThan(100));
          expect(preferences.scrollOffset, closeTo(controller.offset, .01));
          final afterTouch = controller.offset;
          await tester.sendEventToBinding(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: start,
              scrollDelta: const Offset(0, 160),
            ),
          );
          await tester.pumpAndSettle();
          expect(controller.offset, greaterThan(afterTouch));
          expect(preferences.scrollOffset, closeTo(controller.offset, .01));
          final saved = controller.offset;
          preferences.setThemeMode(ThemeMode.light);
          await tester.pumpAndSettle();
          expect(controller.offset, closeTo(saved, .01));
          expect(find.byKey(const ValueKey('recipe-79')), findsNothing);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
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
