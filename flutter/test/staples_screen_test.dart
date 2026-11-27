import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cookdex/create_preferences.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/smart_create_protocol.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/staples.dart';
import 'package:cookdex/ui/staples_screen.dart';
import 'package:cookdex/ui/create_settings_screen.dart';
import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shopping_screen_test.dart' show ShoppingFake, item, menu;

class _Service implements ImportService {
  @override
  final platform = _Platform();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Platform implements ImportPlatform {
  @override
  Future<SmartImportSettings> settings() async =>
      SmartImportSettings(hasKey: true, model: 'gemini-3.5-flash-lite');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder _restockButton(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);

void main() {
  test(
    'shared staple matching accepts pantry forms without unrelated foods',
    () {
      for (final (staple, food) in [
        ('salt', 'kosher salt'),
        ('pepper', 'black pepper'),
        ('olive oil', 'extra-virgin olive oil'),
        ('oil', 'extra virgin olive oil'),
        ('butter', 'unsalted butter'),
        ('basic spices', 'ground cumin'),
        ('basic spices', 'dried oregano'),
      ]) {
        expect(
          stapleMatchesFood(staple, food),
          isTrue,
          reason: '$staple / $food',
        );
        expect(isStaple(food, [staple]), isTrue);
      }
      for (final (staple, food) in [
        ('pepper', 'bell pepper'),
        ('pepper', 'jalapeño pepper'),
        ('pepper', '2 peppers'),
        ('pepper', 'fresh pepper'),
        ('butter', 'peanut butter'),
        ('butter', 'buttermilk'),
        ('basic spices', 'fresh oregano'),
        ('basic spices', 'fresh ginger'),
      ]) {
        expect(
          stapleMatchesFood(staple, food),
          isFalse,
          reason: '$staple / $food',
        );
      }
      expect(
        uncheckedStapleMatch('salt', [
          item('old', 'salt', checked: true),
          item('new', 'kosher salt'),
        ])?.id,
        'new',
      );
      expect(
        uncheckedStapleMatch('salt', [item('old', 'salt', checked: true)]),
        isNull,
      );
    },
  );

  test(
    'shared staples retain the old preference key and exact model input',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'cookdex-shared-staples-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/preferences.json');
      final original = const CreatePreferences.defaults().copyWith(
        staples: ['Kosher salt', 'extra-virgin olive oil', 'rice'],
        avoid: ['peanuts'],
        otherPreferences: 'A crunchy topping',
        servings: 6,
        recipeModel: 'saved-model',
        recipeThinking: 'default',
      );
      await file.writeAsString(jsonEncode({'smartCreate': original.toJson()}));
      final prefs = await LocalPreferences.load(file.path);
      addTearDown(prefs.dispose);
      final before = CreateKitchen(
        ingredients: ['eggs'],
        staples: original.staples,
      ).input;
      expect(prefs.staples, original.staples);
      expect(
        CreateKitchen(ingredients: ['eggs'], staples: prefs.staples).input,
        before,
      );
      prefs.setStaples([...prefs.staples, 'Oats']);
      await prefs.flush();
      final saved = jsonDecode(await file.readAsString()) as Map;
      expect(saved.containsKey('staples'), isFalse);
      expect(
        saved['smartCreate'],
        original.copyWith(staples: [...original.staples, 'Oats']).toJson(),
      );
      final loaded = await LocalPreferences.load(file.path);
      addTearDown(loaded.dispose);
      expect(loaded.staples, [...original.staples, 'Oats']);
      loaded.setStaples([]);
      await loaded.flush();
      final empty = await LocalPreferences.load(file.path);
      addTearDown(empty.dispose);
      expect(empty.staples, isEmpty);
    },
  );

  Future<(RecipeStore, ShoppingFake)> mount(
    WidgetTester tester, {
    List<String> staples = const ['salt', 'butter'],
    List<ShoppingItem> shopping = const [],
  }) async {
    final preferences = LocalPreferences.memory()..setStaples(staples);
    final repository = ShoppingFake([], shopping);
    final store = RecipeStore(repository, preferences);
    await store.initialize();
    addTearDown(() {
      store.dispose();
      preferences.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: StaplesScreen(store: store),
      ),
    );
    await tester.pumpAndSettle();
    return (store, repository);
  }

  testWidgets('On your list shares everyday and compound staple matching', (
    tester,
  ) async {
    await mount(
      tester,
      staples: ['rice', 'flour', 'sugar', 'salt', 'pepper'],
      shopping: [
        item('rice', 'steamed rice'),
        item('flour', 'all-purpose flour'),
        item('sugar', 'brown sugar'),
        item('seasoning', 'salt and pepper'),
      ],
    );
    for (final name in ['rice', 'flour', 'salt', 'pepper']) {
      expect(
        tester.widget<IconButton>(
          _restockButton('$name is on your list'),
        ).onPressed,
        isNull,
      );
    }
    expect(
      tester.widget<IconButton>(
        _restockButton('Add sugar to shopping list'),
      ).onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'staples edit, add and remove share preferences without editing shopping',
    (tester) async {
      final (store, repository) = await mount(
        tester,
        shopping: [item('b', 'butter')],
      );
      await tester.tap(find.text('Add staple'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).autofocus,
        isFalse,
      );
      await tester.enterText(find.byType(TextField), 'Salt');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('This staple is already saved.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Rice');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(store.preferences.createPreferences.staples, [
        'salt',
        'butter',
        'Rice',
      ]);
      await tester.tap(find.byTooltip('Rice options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Brown rice');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.preferences.staples.last, 'Rice');
      await tester.tap(find.byTooltip('Rice options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Brown rice');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.preferences.staples.last, 'Brown rice');
      await tester.tap(find.byTooltip('butter options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove butter?'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(store.preferences.staples, ['salt', 'Brown rice']);
      expect(store.shopping.single.name, 'butter');
      expect(repository.edits, 0);
    },
  );

  testWidgets('staple labels and edits preserve the exact stored case', (
    tester,
  ) async {
    final (store, _) = await mount(
      tester,
      staples: ['sea salt', 'eVOO', 'MSG'],
    );
    for (final name in store.preferences.staples) {
      expect(find.text(name), findsOneWidget);
      expect(find.byTooltip('$name options'), findsOneWidget);
      expect(find.byTooltip('Add $name to shopping list'), findsOneWidget);
    }
    await tester.tap(find.text('eVOO'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'eVOO',
    );
    await tester.enterText(find.byType(TextField), 'eV Olive Oil');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('eV Olive Oil'), findsOneWidget);
    expect(store.preferences.staples, ['sea salt', 'eV Olive Oil', 'MSG']);
  });

  testWidgets(
    'restock shows concise unchecked status and preserves checked rows',
    (tester) async {
      final checked = item(
        'b',
        'butter',
        checked: true,
        quantity: '1 lb',
        sources: ['recipe-b'],
      );
      final (store, repository) = await mount(
        tester,
        shopping: [
          item('s', 'kosher salt', category: 'pantry'),
          checked,
        ],
      );
      expect(find.text('On your list'), findsOneWidget);
      expect(find.text('Add to shopping list'), findsNothing);
      expect(find.text('salt'), findsOneWidget);
      expect(find.text('butter'), findsOneWidget);
      expect(store.preferences.staples, ['salt', 'butter']);
      expect(
        tester
            .widget<IconButton>(_restockButton('salt is on your list'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Add butter to shopping list'));
      await tester.pumpAndSettle();
      expect(repository.lastEdit, isA<ShoppingEdit_AddManualItems>());
      expect((repository.lastEdit as ShoppingEdit_AddManualItems).names, [
        'butter',
      ]);
      expect(
        store.shopping.where((row) => row.id == 'b').single,
        same(checked),
      );
      expect(
        store.shopping.where((row) => !row.checked && row.name == 'butter'),
        hasLength(1),
      );
      expect(
        tester
            .widget<IconButton>(_restockButton('butter is on your list'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'restock failures remain retryable and repeated taps send one write',
    (tester) async {
      final (store, repository) = await mount(tester, staples: ['salt']);
      repository.fail = true;
      await tester.tap(find.byTooltip('Add salt to shopping list'));
      await tester.pumpAndSettle();
      expect(find.text('Could not add. Try again.'), findsOneWidget);
      expect(store.shopping, isEmpty);
      repository.fail = false;
      final gate = Completer<void>();
      repository.gate = gate;
      await tester.tap(find.byTooltip('Add salt to shopping list'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(_restockButton('Add salt to shopping list'))
            .onPressed,
        isNull,
      );
      expect(repository.edits, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Could not add. Try again.'), findsNothing);
      expect(store.shopping, hasLength(1));
    },
  );

  testWidgets('narrow maximum text keeps staple controls and dialog usable', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await mount(
      tester,
      staples: ['extra-virgin olive oil', 'ground coriander'],
    );
    final addButton = find.ancestor(
      of: find.text('Add staple'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    final footerBounds = tester.getRect(addButton);
    expect(footerBounds.width, 288);
    expect(find.text('Add staple').hitTestable(), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('staple-extra-virgin olive oil')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    for (final tooltip in [
      'Add extra-virgin olive oil to shopping list',
      'extra-virgin olive oil options',
    ]) {
      final target = find.byTooltip(tooltip);
      expect(target.hitTestable(), findsOneWidget);
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
    final lastRow = find.byKey(const ValueKey('staple-ground coriander'));
    await tester.scrollUntilVisible(
      lastRow,
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(lastRow).bottom, lessThanOrEqualTo(footerBounds.top));
    expect(tester.getRect(addButton), footerBounds);
    expect(find.text('Add staple').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Add staple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a staple name.'), findsOneWidget);
    expect(find.text('Cancel').hitTestable(), findsOneWidget);
    expect(find.text('Add').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final entry in ['Shopping list', 'Settings', 'Smart Create settings']) {
    testWidgets('$entry opens shared staples and returns with edits retained', (
      tester,
    ) async {
      final prefs = LocalPreferences.memory()..setStaples(['salt', 'butter']);
      final original = prefs.createPreferences.toJson();
      final store = RecipeStore(ShoppingFake([], []), prefs);
      await store.initialize();
      addTearDown(() {
        store.dispose();
        prefs.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Builder(
            builder: (context) => switch (entry) {
              'Shopping list' => ShoppingScreen(
                store: store,
                onSaveText: (_) async {},
              ),
              'Settings' => SettingsScreen(
                readHasPrevious: () => false,
                syncSummary: 'Not paired',
                onStaples: () => openStaples(context, store: store),
                shoppingKeepAwake: false,
                onShoppingKeepAwake: (_) {},
                recipeTextScale: 1,
                onRecipeTextScale: (_) {},
                isAndroid: true,
                wallpaperColors: false,
                onWallpaperColors: (_) {},
                version: '1.10.5+20005',
              ),
              _ => CreateSettingsScreen(
                preferences: prefs,
                service: _Service(),
                onStaples: (context) => openStaples(context, store: store),
                lastDiagnostic: () async => null,
                clearDiagnostic: () async {},
              ),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> open() async {
        if (entry == 'Shopping list') {
          await menu(tester, 'Staples');
        } else {
          if (entry == 'Settings') {
            await tester.scrollUntilVisible(
              find.text('Staples'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await tester.tap(find.text('Staples'));
          await tester.pumpAndSettle();
        }
      }

      await open();
      expect(find.byType(StaplesScreen), findsOneWidget);
      await tester.tap(find.text('salt'));
      await tester.pumpAndSettle();
      expect(find.text('Rename staple'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'salt',
      );
      await tester.enterText(find.byType(TextField), 'sea salt');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(prefs.staples, ['sea salt', 'butter']);
      final expected = Map<String, dynamic>.from(original)
        ..['staples'] = ['sea salt', 'butter'];
      expect(prefs.createPreferences.toJson(), expected);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StaplesScreen), findsNothing);
      expect(find.text(entry), findsOneWidget);
      if (entry == 'Smart Create settings') {
        expect(find.text('sea salt'), findsOneWidget);
      }
      await open();
      expect(find.text('sea salt'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
