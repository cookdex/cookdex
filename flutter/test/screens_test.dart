import 'dart:async';
import 'dart:typed_data';

import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/app_platform.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Recipe _recipe(
  String id, {
  List<String>? steps,
  String notes = 'Keep chilled.',
  String? title,
  String description = 'A bright, smooth bowl of garden vegetables.',
  String servings = '4',
  List<String> tags = const ['Dinner', 'Quick'],
}) => Recipe(
  id: id,
  favorite: false,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-02',
  revision: 1,
  fields: RecipeFields(
    title: title ?? 'Green soup $id',
    description: description,
    servings: servings,
    prepTime: '10 min',
    cookTime: '20 min',
    totalTime: '30 min',
    source: 'https://example.com/soup',
    tags: tags,
    notes: notes,
    ingredients: const [
      Ingredient(
        amount: Amount.rational(numerator: 33, denominator: 100),
        unit: 'cup',
        name: 'cream',
        prepNote: 'at room temperature',
        optional: true,
        section: 'For the soup',
      ),
      Ingredient(
        amount: Amount.toTaste(),
        unit: '',
        name: 'salt',
        prepNote: '',
        optional: false,
        section: 'For the soup',
      ),
    ],
    steps:
        steps ??
        ['Warm the pan and add the vegetables.', 'Stir in cream and serve.'],
  ),
);

class _Repository implements RecipeRepository {
  _Repository(this.recipes);
  List<Recipe> recipes;
  final events = StreamController<CollectionEvent>.broadcast();
  int calls = 0, generation = 0;
  CollectionSnapshot get current => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: generation,
    summaries: recipes
        .map(
          (r) => RecipeSummary(
            id: r.id,
            title: r.fields.title,
            description: r.fields.description,
            ingredients: r.fields.ingredients.map((i) => i.name).toList(),
            tags: r.fields.tags,
            notes: r.fields.notes,
            favorite: r.favorite,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            servings: r.fields.servings,
            prepTime: r.fields.prepTime,
            cookTime: r.fields.cookTime,
            totalTime: r.fields.totalTime,
            revision: r.revision,
          ),
        )
        .toList(),
    shopping: [],
    conflicts: [],
    hasPrevious: false,
  );
  @override
  Future<CollectionSnapshot> snapshot() async {
    calls++;
    return current;
  }

  @override
  Stream<CollectionEvent> subscribe() => events.stream;
  @override
  Future<Recipe?> detail(String id) async {
    calls++;
    return recipes.where((r) => r.id == id).firstOrNull;
  }

  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async {
    calls++;
    return ['33/100', 'to taste'];
  }

  @override
  Future<CollectionSnapshot> favorite(
    int generation,
    String id,
    bool value,
  ) async {
    calls++;
    recipes = recipes
        .map(
          (r) => r.id == id
              ? Recipe(
                  id: r.id,
                  fields: r.fields,
                  favorite: value,
                  createdAt: r.createdAt,
                  updatedAt: r.updatedAt,
                  revision: r.revision + 1,
                )
              : r,
        )
        .toList();
    this.generation++;
    return current;
  }

  @override
  Future<CollectionSnapshot> delete(int generation, String id) async =>
      throw UnimplementedError();
  @override
  Future<BackupPreview> previewRestore(Uint8List bytes) async =>
      throw UnimplementedError();
  @override
  Future<CollectionSnapshot> restore(BackupPreview preview) async =>
      throw UnimplementedError();
  @override
  Future<void> close() => events.close();
}

Widget _host(Widget child, {double scale = 1}) => MaterialApp(
  theme: cookdexTheme(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: child),
);

class _TestPlatform extends AppPlatform {
  @override
  bool get isAndroid => true;
  @override
  Future<void> backgroundTask() async {}
  @override
  Future<void> openSource(String url) async {}
  @override
  Future<Uint8List?> pickRecipeZip() async => null;
  @override
  Future<String> privateRoot() async => throw UnimplementedError();
  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
  @override
  Future<ColorScheme?> wallpaperColorScheme({
    Brightness brightness = Brightness.dark,
  }) async => null;
}

void main() {
  testWidgets('matching choice chips and raw card metadata with no empty gap', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final preferences = LocalPreferences.memory();
    final store = RecipeStore(
      _Repository([
        _recipe('one', description: '', servings: '2 large pancakes'),
      ]),
      preferences,
    );
    await store.initialize();
    addTearDown(() {
      store.dispose();
      preferences.dispose();
    });
    await tester.pumpWidget(
      _host(
        RecipesScreen(
          store: store,
          preferences: preferences,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilterChip, 'Favorites'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Recently edited'), findsOneWidget);
    expect(find.byTooltip('Switch to Compact view'), findsOneWidget);
    expect(find.byIcon(Symbols.arrow_drop_down), findsOneWidget);
    expect(find.text('2 large pancakes'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.byIcon(Symbols.inventory_2), findsOneWidget);
    expect(find.byIcon(Symbols.schedule), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('2 large pancakes')).dy -
          tester.getBottomLeft(find.text('Green soup one')).dy,
      lessThanOrEqualTo(12),
    );
    await tester.ensureVisible(find.byKey(const Key('recipe-view')));
    await tester.tap(find.byKey(const Key('recipe-view')));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemButton), findsNothing);
    expect(find.byTooltip('Switch to Cards view'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('recipe-view')),
        matching: find.byIcon(Symbols.view_agenda),
      ),
      findsOneWidget,
    );
    expect(preferences.view, RecipeView.compact);
    expect(find.text('Dinner · Quick'), findsOneWidget);
    await tester.tap(find.byKey(const Key('recipe-view')));
    await tester.pumpAndSettle();
    expect(preferences.view, RecipeView.cards);
    expect(find.byTooltip('Switch to Compact view'), findsOneWidget);
    final favorites = find.widgetWithText(FilterChip, 'Favorites');
    final originalSize = tester.getSize(favorites);
    final unselected = tester.widget<FilterChip>(favorites);
    expect((unselected.avatar! as Icon).fill, 0);
    await tester.ensureVisible(favorites);
    await tester.tap(favorites);
    await tester.pumpAndSettle();
    final selected = tester.widget<FilterChip>(favorites);
    expect(selected.selected, isTrue);
    expect((selected.avatar! as Icon).fill, 1);
    expect(selected.selectedColor, isNotNull);
    expect(tester.getSize(favorites), originalSize);
    await tester.tap(favorites);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(favorites).selected, isFalse);
    expect(tester.getSize(favorites), originalSize);
  });

  testWidgets(
    'Cards preserve chosen tag spellings and small muted two-line descriptions',
    (tester) async {
      final preferences = LocalPreferences.memory();
      final store = RecipeStore(
        _Repository([
          _recipe(
            'one',
            tags: ['Dinner', 'DINNER', 'Quick'],
            description: 'A description long enough to wrap across multiple lines when viewed on a phone.',
          ),
        ]),
        preferences,
      );
      await store.initialize();
      addTearDown(() {
        store.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        _host(
          RecipesScreen(
            store: store,
            preferences: preferences,
            onOpenRecipe: (_) {},
            onAdd: () {},
            onActions: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dinner'), findsOneWidget);
      expect(find.text('Quick'), findsOneWidget);
      expect(find.text('DINNER'), findsOneWidget);
      final description = tester.widget<Text>(
        find.textContaining('A description long enough'),
      );
      final title = tester.widget<Text>(find.text('Green soup one'));
      expect(description.maxLines, 2);
      expect(description.overflow, TextOverflow.ellipsis);
      expect(description.style!.fontSize!, lessThan(title.style!.fontSize!));
      expect(
        description.style!.color,
        Theme.of(tester.element(find.text('Dinner')))
            .colorScheme
            .onSurfaceVariant,
      );
    },
  );

  testWidgets(
    'Compact gives titles the width, aligns stars and fits ten phone rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = LocalPreferences.memory()
        ..setView(RecipeView.compact);
      final store = RecipeStore(
        _Repository(
          List.generate(
            20,
            (i) => _recipe(
              '$i',
              title: 'Recipe ${i.toString().padLeft(2, '0')}',
              tags: i == 1 ? [] : ['sides', 'potatoes', 'unused'],
            ),
          ),
        ),
        preferences,
      );
      await store.initialize();
      addTearDown(() {
        store.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        _host(
          RecipesScreen(
            store: store,
            preferences: preferences,
            onOpenRecipe: (_) {},
            onAdd: () {},
            onActions: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(find.text('Recipe 00'));
      final star = tester.getRect(find.byTooltip('Favorite Recipe 00'));
      expect(
        tester
            .renderObject<RenderBox>(find.text('Recipe 00'))
            .constraints
            .maxWidth,
        310,
      );
      expect(first.left + 310, star.left);
      expect(
        tester.getRect(find.byTooltip('Favorite Recipe 01')).right,
        star.right,
      );
      expect(tester.getSize(find.byKey(const ValueKey('0'))).height, 53);
      expect(tester.getSize(find.byKey(const ValueKey('1'))).height, 53);
      expect(find.text('sides · potatoes · unused'), findsWidgets);
      expect(
        tester
            .widget<Text>(find.text('sides · potatoes · unused').first)
            .maxLines,
        1,
      );
      final rows = find.textContaining(RegExp(r'^Recipe \d'));
      final visible = rows.evaluate().where((element) {
        final rect = tester.getRect(find.byWidget(element.widget));
        return rect.top >= 0 && rect.bottom <= 760;
      });
      expect(visible.length, greaterThanOrEqualTo(10));
      expect(find.byType(Divider), findsWidgets);
      await tester.binding.setSurfaceSize(const Size(1000, 760));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('0'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('1'))).dy,
      );
      expect(tester.getTopLeft(find.text('Recipe 01')).dx, greaterThan(500));
    },
  );

  testWidgets(
    'detail adds scrolled name and keeps Cooking at standard height',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = LocalPreferences.memory();
      final store = RecipeStore(
        _Repository([
          _recipe(
            'one',
            servings: '6-8 Servings',
            steps: List.generate(20, (i) => 'Cook step $i'),
          ),
        ]),
        preferences,
      );
      final cook = CookController(
        preferences: preferences,
        setWake: (_) async {},
      );
      await store.initialize();
      addTearDown(() {
        cook.dispose();
        store.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        _host(
          RecipeDetail(
            store: store,
            recipeId: 'one',
            cook: cook,
            onBack: () {},
            onActions: () {},
            onEdit: () {},
            onSource: (_) async {},
            onAddToShopping: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byKey(const Key('recipe-bar-title')),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
      expect(find.text('6–8'), findsOneWidget);
      expect(find.text('Total 30 min'), findsOneWidget);
      final toolbar = tester.getRect(find.byKey(const Key('recipe-toolbar')));
      final viewport = tester.getRect(
        find.byKey(const PageStorageKey('recipe-one')),
      );
      expect(
        tester.getCenter(find.byKey(const Key('cook-toggle'))).dx,
        greaterThan(
          tester.getCenter(find.byKey(const Key('recipe-bar-title'))).dx,
        ),
      );
      await tester.drag(
        find.byKey(const PageStorageKey('recipe-one')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recipe-bar-title')), findsOneWidget);
      expect(tester.getRect(find.byKey(const Key('recipe-toolbar'))), toolbar);
      expect(
        tester.getRect(find.byKey(const PageStorageKey('recipe-one'))),
        viewport,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.byKey(const Key('recipe-bar-title')),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();
      expect(find.text('Cooking'), findsOneWidget);
      final button = find.byKey(const Key('cook-toggle'));
      final surface = find.descendant(
        of: button,
        matching: find.byType(Material),
      );
      expect(tester.getSize(surface).height, 36);
      expect(
        tester.getCenter(button).dy,
        tester.getCenter(find.byTooltip('Edit recipe')).dy,
      );
      expect(tester.getSize(button).height, 48);
    },
  );

  testWidgets(
    'favorite changes silently while shell cooking Next stays tappable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final preferences = LocalPreferences.memory();
      final store = RecipeStore(_Repository([_recipe('one')]), preferences);
      await store.initialize();
      await tester.pumpWidget(
        CookdexApp(store: store, platform: _TestPlatform()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Green soup one'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Favorite recipe'));
      await tester.pumpAndSettle();
      expect(store.summaries.single.favorite, isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Next').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(preferences.cookStep('one'), 1);
      expect(find.text('2/2'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    },
  );

  testWidgets(
    'five-field search stays local and no-match Reset restores defaults',
    (tester) async {
      final preferences = LocalPreferences.memory();
      final repository = _Repository([_recipe('one')]);
      final store = RecipeStore(repository, preferences);
      await store.initialize();
      addTearDown(() {
        store.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        _host(
          RecipesScreen(
            store: store,
            preferences: preferences,
            onOpenRecipe: (_) {},
            onAdd: () {},
            onActions: (_) {},
          ),
        ),
      );
      final calls = repository.calls;
      await tester.enterText(
        find.byKey(const Key('recipe-search')),
        'SOUP cream',
      );
      await tester.pumpAndSettle();
      expect(find.text('Green soup one'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('recipe-search')), 'chilled');
      await tester.pumpAndSettle();
      expect(find.text('No matching recipes'), findsOneWidget);
      await tester.tap(find.byTooltip('Search fields'));
      await tester.pumpAndSettle();
      for (final label in [
        'Title',
        'Ingredients',
        'Tags',
        'Notes',
        'Description',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      expect(store.visibleRecipes, hasLength(1));
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-search')),
        'title:soup',
      );
      await tester.pumpAndSettle();
      expect(find.text('No matching recipes'), findsOneWidget);
      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(preferences.searchFields, LocalPreferences.defaultSearchFields);
      expect(preferences.query, isEmpty);
      expect(repository.calls, calls);
    },
  );

  testWidgets('favorite toggles silently and both menu gestures agree', (
    tester,
  ) async {
    final preferences = LocalPreferences.memory();
    final repository = _Repository([_recipe('one'), _recipe('two')]);
    final store = RecipeStore(repository, preferences);
    await store.initialize();
    addTearDown(() {
      store.dispose();
      preferences.dispose();
    });
    final actions = <String>[];
    await tester.pumpWidget(
      _host(
        RecipesScreen(
          store: store,
          preferences: preferences,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (r) => actions.add(r.id),
        ),
      ),
    );
    await tester.longPress(find.text('Green soup one'));
    await tester.tap(
      find.text('Green soup one'),
      buttons: kSecondaryMouseButton,
    );
    expect(actions, ['one', 'one']);
    final unaffectedRow = tester.widget(find.byKey(const ValueKey('two')));
    await tester.tap(find.byTooltip('Favorite Green soup one'));
    await tester.pumpAndSettle();
    expect(store.summaries.firstWhere((r) => r.id == 'one').favorite, isTrue);
    expect(
      identical(
        tester.widget(find.byKey(const ValueKey('two'))),
        unaffectedRow,
      ),
      isTrue,
    );
    expect(find.byType(SnackBar), findsNothing);
    await tester.tap(find.byTooltip('Unfavorite Green soup one'));
    await tester.pumpAndSettle();
    expect(store.summaries.firstWhere((r) => r.id == 'one').favorite, isFalse);
    expect(find.byType(SnackBar), findsNothing);
  });

  for (final width in [320.0, 390.0, 1000.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('all views and detail fit width $width scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, width == 1000 ? 600 : 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = LocalPreferences.memory();
        final store = RecipeStore(
          _Repository([_recipe('one'), _recipe('two')]),
          preferences,
        );
        final cook = CookController(
          preferences: preferences,
          setWake: (_) async {},
        );
        await store.initialize();
        addTearDown(() {
          cook.dispose();
          store.dispose();
          preferences.dispose();
        });
        await tester.pumpWidget(
          _host(
            RecipesScreen(
              store: store,
              preferences: preferences,
              onOpenRecipe: (_) {},
              onAdd: () {},
              onActions: (_) {},
            ),
            scale: scale,
          ),
        );
        for (final view in RecipeView.values) {
          preferences.setView(view);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          _host(
            RecipeDetail(
              store: store,
              recipeId: 'one',
              cook: cook,
              onBack: () {},
              onActions: () {},
              onEdit: () {},
              onSource: (_) async {},
              onAddToShopping: () {},
            ),
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('33/100 cup cream (optional)'), findsOneWidget);
        expect(find.text('salt, to taste'), findsOneWidget);
        cook.toggle();
        await tester.pumpAndSettle();
        expect(find.text('Previous'), findsOneWidget);
        expect(find.text('Next'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (width == 1000) {
          tester.view.physicalSize = const Size(750, 500);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets(
    'cook step tap and pinned controls persist checks and bounded position',
    (tester) async {
      final preferences = LocalPreferences.memory();
      final store = RecipeStore(_Repository([_recipe('one')]), preferences);
      final cook = CookController(
        preferences: preferences,
        setWake: (_) async {},
      );
      await store.initialize();
      addTearDown(() {
        cook.dispose();
        store.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        _host(
          RecipeDetail(
            store: store,
            recipeId: 'one',
            cook: cook,
            onBack: () {},
            onActions: () {},
            onEdit: () {},
            onSource: (_) async {},
            onAddToShopping: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cook'));
      await tester.pumpAndSettle();
      expect(find.text('Cooking'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(cook.step, 1);
      expect(preferences.cookStep('one'), 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Done'))
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('salt, to taste'));
      await tester.tap(find.text('salt, to taste'));
      await tester.pumpAndSettle();
      expect(preferences.cookChecks('one'), {1});
      await tester.ensureVisible(
        find.text('Warm the pan and add the vegetables.'),
      );
      await tester.tap(find.text('Warm the pan and add the vegetables.'));
      await tester.pumpAndSettle();
      expect(cook.step, 0);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Previous'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'empty Notes is absent and recipe without steps cannot enter cook mode',
    (tester) async {
      final preferences = LocalPreferences.memory();
      final store = RecipeStore(
        _Repository([_recipe('one', steps: [], notes: '')]),
        preferences,
      );
      final cook = CookController(
        preferences: preferences,
        setWake: (_) async {},
      );
      await store.initialize();
      addTearDown(() {
        cook.dispose();
        store.dispose();
        preferences.dispose();
      });
      await tester.pumpWidget(
        _host(
          RecipeDetail(
            store: store,
            recipeId: 'one',
            cook: cook,
            onBack: () {},
            onActions: () {},
            onEdit: () {},
            onSource: (_) async {},
            onAddToShopping: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Notes'), findsNothing);
      expect(find.text('Steps'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cook'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('scroll hides FAB, keeps search pinned and returns FAB upward', (
    tester,
  ) async {
    final preferences = LocalPreferences.memory();
    final store = RecipeStore(
      _Repository(List.generate(30, (i) => _recipe('$i'))),
      preferences,
    );
    await store.initialize();
    addTearDown(() {
      store.dispose();
      preferences.dispose();
    });
    await tester.pumpWidget(
      _host(
        RecipesScreen(
          store: store,
          preferences: preferences,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (_) {},
        ),
      ),
    );
    await tester.drag(
      find.byWidgetPredicate((w) => w is CustomScrollView),
      const Offset(0, -450),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-recipe')), findsOneWidget);
    expect(find.byKey(const Key('add-recipe')).hitTestable(), findsNothing);
    final pinnedSearchTop = tester
        .getTopLeft(find.byKey(const Key('recipe-search')))
        .dy;
    expect(pinnedSearchTop, lessThanOrEqualTo(16));
    await tester.drag(
      find.byWidgetPredicate((w) => w is CustomScrollView),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('recipe-search'))).dy,
      closeTo(pinnedSearchTop, 1),
    );
    await tester.drag(
      find.byWidgetPredicate((w) => w is CustomScrollView),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-recipe')), findsOneWidget);
  });

  testWidgets('last recipe star stays tappable with the FAB visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = LocalPreferences.memory();
    final store = RecipeStore(
      _Repository(List.generate(12, (i) => _recipe('$i'))),
      preferences,
    );
    final scroll = ScrollController();
    await store.initialize();
    addTearDown(() {
      scroll.dispose();
      store.dispose();
      preferences.dispose();
    });
    await tester.pumpWidget(
      _host(
        RecipesScreen(
          store: store,
          preferences: preferences,
          controller: scroll,
          onOpenRecipe: (_) {},
          onAdd: () {},
          onActions: (_) {},
        ),
      ),
    );
    // SliverList estimates extent before all rows have been measured.
    for (var i = 0; i < 3; i++) {
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    final last = store.visibleRecipes.last;
    final star = find.byTooltip('Favorite ${last.title}');
    final fab = find.byKey(const Key('add-recipe'));
    expect(star, findsOneWidget);
    expect(fab, findsOneWidget);
    expect(tester.getRect(star).overlaps(tester.getRect(fab)), isFalse);
    expect(
      tester.getRect(find.byKey(ValueKey(last.id))).bottom,
      lessThanOrEqualTo(tester.getRect(fab).top),
    );
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(store.summaries.firstWhere((r) => r.id == last.id).favorite, isTrue);
  });

  testWidgets(
    'refresh error is visible without pretending cached recipes disappeared',
    (tester) async {
      final preferences = LocalPreferences.memory();
      final store = RecipeStore(_Repository([_recipe('one')]), preferences);
      await store.initialize();
      addTearDown(() {
        store.dispose();
        preferences.dispose();
      });
      store.error = 'synthetic storage error';
      await tester.pumpWidget(
        _host(
          RecipesScreen(
            store: store,
            preferences: preferences,
            onOpenRecipe: (_) {},
            onAdd: () {},
            onActions: (_) {},
          ),
        ),
      );
      expect(find.text('Recipes could not be refreshed'), findsOneWidget);
      expect(find.text('Green soup one'), findsOneWidget);
      expect(find.text('No recipes caught yet'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Recipes could not be refreshed'), findsNothing);
    },
  );
}
