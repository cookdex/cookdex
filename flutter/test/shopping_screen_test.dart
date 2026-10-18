import 'dart:async';

import 'package:cookdex/app_platform.dart';
import 'package:cookdex/export_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe, summary;

ShoppingItem item(
  String id,
  String name, {
  bool checked = false,
  String quantity = '',
  List<String> sources = const [],
  List<String> scales = const [],
  String category = 'other',
}) => ShoppingItem(
  categoryId: category,
  id: id,
  name: name,
  measures: const [],
  contributorScales: scales,
  contributorIds: sources,
  checked: checked,
  quantityText: quantity,
);

class FakeShoppingUndo implements ShoppingUndo {
  FakeShoppingUndo(this.before, this.after);
  final List<ShoppingItem> before, after;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ShoppingFake extends FakeRepository implements ShoppingRepository {
  ShoppingFake(super.recipes, [List<ShoppingItem> items = const []])
    : items = [...items];
  List<ShoppingItem> items;
  List<ShoppingCategory> categories = [
    const ShoppingCategory(id: 'produce', name: 'Produce'),
    const ShoppingCategory(id: 'pantry', name: 'Pantry'),
    const ShoppingCategory(id: 'other', name: 'Other'),
  ];
  ShoppingEdit? lastEdit;
  List<int>? selected;
  int edits = 0;
  bool fail = false, failUndo = false;
  Completer<void>? gate;
  @override
  CollectionSnapshot get current => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: [...categories],
    generation: generation,
    summaries: recipes.values.map(summary).toList(),
    shopping: [...items],
    conflicts: const [],
    hasPrevious: generation > 0,
  );
  Future<ShoppingResult> _result(List<ShoppingItem> before) async {
    if (gate != null) await gate!.future;
    generation++;
    return ShoppingResult(
      snapshot: current,
      undo: FakeShoppingUndo(before, [...items]),
    );
  }

  @override
  Future<ShoppingResult> editShopping(int generation, ShoppingEdit edit) async {
    edits++;
    lastEdit = edit;
    if (fail) {
      throw const ServiceError(
        code: ErrorCode.storage,
        message: 'Write failed.',
      );
    }
    final before = [...items];
    switch (edit) {
      case ShoppingEdit_AddManual(:final text):
        items.add(item('manual-$edits', text.trim()));
      case ShoppingEdit_Edit(:final id, :final text):
        items = [
          for (final row in items)
            if (row.id == id)
              item(id, text.trim(), category: row.categoryId)
            else
              row,
        ];
      case ShoppingEdit_Check(:final ids, :final checked):
        items = [
          for (final row in items)
            if (ids.contains(row.id))
              item(
                row.id,
                row.name,
                checked: checked,
                quantity: row.quantityText,
                sources: row.contributorIds,
                category: row.categoryId,
              )
            else
              row,
        ];
      case ShoppingEdit_Remove(:final ids):
        items = items.where((row) => !ids.contains(row.id)).toList();
      case ShoppingEdit_Move(:final id, :final categoryId, :final beforeId):
        final row = items.firstWhere((row) => row.id == id);
        items.removeWhere((row) => row.id == id);
        final moved = ShoppingItem(
          id: row.id,
          name: row.name,
          measures: row.measures,
          contributorScales: const [],
          contributorIds: row.contributorIds,
          checked: row.checked,
          quantityText: row.quantityText,
          categoryId: categoryId,
        );
        final before = beforeId == null
            ? -1
            : items.indexWhere((row) => row.id == beforeId);
        items.insert(before < 0 ? items.length : before, moved);
      case ShoppingEdit_ReorderItems(:final ids):
        final byId = {for (final row in items) row.id: row};
        var index = 0;
        items = [
          for (final row in items)
            if (ids.contains(row.id)) byId[ids[index++]]! else row,
        ];
      case ShoppingEdit_AddCategory(:final name):
        categories.add(ShoppingCategory(id: 'category-$edits', name: name));
      case ShoppingEdit_RenameCategory(:final id, :final name):
        categories = [
          for (final category in categories)
            if (category.id == id)
              ShoppingCategory(id: id, name: name)
            else
              category,
        ];
      case ShoppingEdit_DeleteCategory(:final id):
        categories.removeWhere((category) => category.id == id);
        items = [
          for (final row in items)
            if (row.categoryId == id)
              item(
                row.id,
                row.name,
                checked: row.checked,
                quantity: row.quantityText,
                sources: row.contributorIds,
              )
            else
              row,
        ];
      case ShoppingEdit_ReorderCategories(:final ids):
        final byId = {for (final category in categories) category.id: category};
        categories = [for (final id in ids) byId[id]!];
    }
    return _result(before);
  }

  @override
  Future<ShoppingResult> addShopping(
    int generation,
    String id,
    List<int> indices,
  ) async {
    selected = [...indices];
    if (fail) {
      throw const ServiceError(
        code: ErrorCode.storage,
        message: 'Write failed.',
      );
    }
    final before = [...items];
    for (final index in indices) {
      final ingredient = recipes[id]!.fields.ingredients[index];
      items.add(item('recipe-$id-$index', ingredient.name, sources: [id]));
    }
    return _result(before);
  }

  @override
  Future<CollectionSnapshot> undoShopping(
    int generation,
    ShoppingUndo undo,
  ) async {
    if (failUndo) {
      throw const ServiceError(
        code: ErrorCode.staleWrite,
        message: 'Shopping list changed.',
      );
    }
    items = [...(undo as FakeShoppingUndo).before];
    this.generation++;
    return current;
  }
}

class _ShoppingAppPlatform implements AppPlatform {
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

class _ShoppingSavePlatform implements ExportPlatform {
  _ShoppingSavePlatform({required this.fail});
  final bool fail;
  int saves = 0;

  @override
  Future<ExportOutcome> save(String text, {required String filename}) async {
    saves++;
    if (fail) throw PlatformException(code: 'write', message: 'Save failed.');
    return ExportOutcome.saved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<(RecipeStore, ShoppingFake)> setup(
  List<ShoppingItem> items, {
  List<Recipe>? recipes,
  List<ShoppingCategory>? categories,
}) async {
  final repo = ShoppingFake(
    recipes ?? [recipe('a'), recipe('b', title: 'Soup')],
    items,
  );
  if (categories != null) repo.categories = [...categories];
  final prefs = LocalPreferences.memory();
  final store = RecipeStore(repo, prefs);
  await store.initialize();
  addTearDown(() {
    store.dispose();
    prefs.dispose();
  });
  return (store, repo);
}

Future<void> screen(
  WidgetTester tester,
  RecipeStore store, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool reduceMotion = false,
  Future<void> Function()? save,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: ShoppingScreen(store: store, onSaveText: (_) async => save?.call()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder input() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Add an item',
);
Future<void> menu(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Shopping list options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'source subtitle omits every multiplier without changing quantity',
    (tester) async {
      final (store, _) = await setup([
        item(
          'a',
          'Flour',
          quantity: '4 cups',
          sources: ['a', 'b'],
          scales: ['×1', '×2'],
        ),
      ]);
      await screen(tester, store);
      expect(find.textContaining('×1'), findsNothing);
      expect(find.textContaining('×2'), findsNothing);
      expect(find.textContaining('4 cups', findRichText: true), findsWidgets);
      expect(store.shopping.single.contributorScales, ['×1', '×2']);
    },
  );
  testWidgets(
    'retained shopping tab reveals latest store data and keeps draft',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (store, _) = await setup([item('a', 'Flour'), item('b', 'Salt')]);
      await tester.pumpWidget(
        CookdexApp(store: store, platform: _ShoppingAppPlatform()),
      );
      await tester.pumpAndSettle();
      Finder destination(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      await tester.tap(destination('Shopping list'));
      await tester.pumpAndSettle();
      final retainedState = tester.state(find.byType(ShoppingScreen));
      expect(find.text('Flour'), findsOneWidget);
      expect(find.text('Salt'), findsOneWidget);
      await tester.enterText(input(), 'Unsubmitted milk');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      await tester.tap(destination('Recipes'));
      await tester.pumpAndSettle();
      expect(find.byType(ShoppingScreen), findsNothing);
      expect(
        tester.state(find.byType(ShoppingScreen, skipOffstage: false)),
        same(retainedState),
      );
      // Use real RecipeStore writes/notifications while the retained tab is hidden.
      await store.editShopping(ShoppingEdit.check(ids: ['a'], checked: true));
      await store.editShopping(ShoppingEdit.remove(ids: ['b']));
      await store.editShopping(const ShoppingEdit.addManual(text: 'Carrots'));
      await tester.pumpAndSettle();

      await tester.tap(destination('Shopping list'));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ShoppingScreen)), same(retainedState));
      expect(find.text('Carrots'), findsOneWidget);
      expect(find.text('Salt'), findsNothing);
      expect(find.text('Checked (1)'), findsOneWidget);
      expect(find.text('Flour'), findsNothing);
      expect(
        tester.widget<TextField>(input()).controller!.text,
        'Unsubmitted milk',
      );
      await tester.tap(find.text('Checked (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Flour'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Flour')).style!.decoration,
        TextDecoration.lineThrough,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final failSave in [false, true]) {
    testWidgets(
      'app shopping save ${failSave ? 'error' : 'success'} replaces local Undo above input',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (store, _) = await setup([item('a', 'Flour'), item('b', 'Salt')]);
        final platform = _ShoppingSavePlatform(fail: failSave);
        await tester.pumpWidget(
          CookdexApp(
            store: store,
            platform: _ShoppingAppPlatform(),
            exportService: ExportService(platform: platform),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Shopping list'));
        await tester.pumpAndSettle();
        await tester.longPress(find.text('Flour'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Undo'), findsOneWidget);
        expect(store.shopping.single.name, 'Salt');
        await menu(tester, 'Save list as text');
        expect(platform.saves, 1);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text('Undo'), findsNothing);
        expect(find.text('Item removed'), findsNothing);
        expect(
          find.text(failSave ? 'Save failed.' : 'Text saved'),
          findsOneWidget,
        );
        final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackbar.duration, Duration(seconds: failSave ? 4 : 2));
        expect(snackbar.persist, isFalse);
        expect(
          ScaffoldMessenger.of(tester.element(find.byType(SnackBar))),
          same(ScaffoldMessenger.of(tester.element(input()))),
        );
        expect(
          tester.getRect(find.byType(SnackBar)).bottom,
          lessThanOrEqualTo(tester.getRect(input()).top),
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsNothing);
        await tester.pump(const Duration(seconds: 4));
        expect(find.byType(SnackBar), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'pinned Enter input validates emptiness and retains failed manual input',
    (tester) async {
      final (store, repo) = await setup([]);
      await screen(tester, store);
      expect(tester.getBottomRight(input()).dy, greaterThan(760));
      await tester.tap(find.byTooltip('Add item'));
      await tester.pumpAndSettle();
      expect(find.text('Enter an item.'), findsOneWidget);
      expect(repo.edits, 0);
      await tester.enterText(input(), 'Milk');
      repo.fail = true;
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Write failed.'), findsOneWidget);
      expect(tester.widget<TextField>(input()).controller!.text, 'Milk');
      repo.fail = false;
      await tester.tap(find.byTooltip('Add item'));
      await tester.pumpAndSettle();
      expect(store.shopping.single.name, 'Milk');
      expect(tester.widget<TextField>(input()).controller!.text, isEmpty);
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Item added'), findsNothing);
    },
  );

  testWidgets(
    'whole rows check, checked collapse, swipe is inert and menu Delete has guarded Undo',
    (tester) async {
      final (store, repo) = await setup([
        item('a', 'Flour', quantity: '2 cups', sources: ['a', 'a', 'b']),
        item('b', 'Salt', quantity: 'to taste', sources: ['a']),
      ]);
      await screen(tester, store);
      expect(find.text('Lemon cake, Soup'), findsOneWidget);
      expect(find.text('Lemon cake'), findsOneWidget);
      expect(find.text('2 cups Flour'), findsOneWidget);
      await tester.tap(find.text('2 cups Flour'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(store.uncheckedShoppingCount, 1);
      expect(find.text('Checked (1)'), findsOneWidget);
      expect(find.text('2 cups Flour'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('Checked (1)'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('2 cups Flour')).style!.decoration,
        TextDecoration.lineThrough,
      );
      await tester.drag(find.byKey(const ValueKey('b')), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(store.shopping.length, 2);
      expect(find.byType(SnackBar), findsNothing);
      await tester.drag(find.byKey(const ValueKey('b')), const Offset(350, 0));
      await tester.pumpAndSettle();
      expect(store.shopping.length, 2);
      await tester.longPress(find.text('to taste Salt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(store.shopping.map((i) => i.name), ['Flour']);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.shopping.length, 2);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('to taste Salt')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      repo.failUndo = true;
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Shopping list changed.'), findsOneWidget);
      expect(store.shopping.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quantity leads the bold name with bounded recipe sources', (
    tester,
  ) async {
    final (store, _) = await setup(
      [
        item('a', 'Flour', quantity: '2 cups', sources: ['a', 'a', 'b', 'c']),
        item('manual', 'Milk', quantity: '1 bottle'),
      ],
      recipes: [
        recipe('a'),
        recipe('b', title: 'Soup'),
        recipe('c', title: 'Pie'),
      ],
    );
    await screen(tester, store);
    expect(find.text('Lemon cake, Soup +1 more'), findsOneWidget);
    final label = tester.widget<Text>(find.text('2 cups Flour'));
    final spans = (label.textSpan! as TextSpan).children!;
    expect((spans.first as TextSpan).text, '2 cups ');
    expect(label.style!.fontWeight, FontWeight.normal);
    expect((spans.last as TextSpan).text, 'Flour');
    expect((spans.last as TextSpan).style!.fontWeight, FontWeight.bold);
    expect(
      tester.getTopLeft(find.text('Lemon cake, Soup +1 more')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('2 cups Flour')).dy),
    );
    final manual = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('1 bottle Milk'),
        matching: find.byType(ListTile),
      ),
    );
    expect(manual.subtitle, isNull);
  });

  testWidgets('check holds visibly, collapses, and uncheck moves back', (
    tester,
  ) async {
    final (store, _) = await setup([item('a', 'Flour'), item('b', 'Salt')]);
    await screen(tester, store);
    await tester.tap(find.text('Flour'));
    await tester.pump();
    expect(store.shopping.first.checked, true);
    expect(find.text('Flour'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Flour')).style!.decoration,
      TextDecoration.lineThrough,
    );
    await tester.pump(const Duration(milliseconds: 299));
    expect(find.text('Checked (1)'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    final fading = tester.widget<Opacity>(
      find
          .ancestor(of: find.text('Flour'), matching: find.byType(Opacity))
          .first,
    );
    expect(fading.opacity, lessThan(1));
    expect(fading.opacity, greaterThan(0));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('Flour'), findsNothing);
    await tester.tap(find.text('Checked (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flour'));
    await tester.pump();
    expect(store.shopping.first.checked, false);
    expect(find.text('Checked (1)'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Checked (1)'), findsNothing);
    expect(find.text('Flour'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Flour')).dy,
      lessThan(tester.getTopLeft(find.text('Salt')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'nine short source rows and category fit phone with 48dp targets',
    (tester) async {
      final (store, _) = await setup([
        for (var i = 0; i < 9; i++)
          item('$i', 'Item $i', quantity: '1 lb', sources: ['a']),
      ]);
      // Reserve the app shell's 80dp navigation bar on a 390x844 phone.
      await screen(tester, store, size: const Size(390, 764));
      final viewport = tester.getRect(
        find.byWidgetPredicate((w) => w is CustomScrollView),
      );
      final lastRow = find.byKey(const ValueKey('8'));
      expect(
        tester.getRect(lastRow).bottom,
        lessThanOrEqualTo(viewport.bottom),
      );
      for (var i = 0; i < 9; i++) {
        final row = find.byKey(ValueKey('$i'));
        final tile = find.descendant(of: row, matching: find.byType(ListTile));
        expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(tile).height, lessThanOrEqualTo(64));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('source-free rows retain 48dp targets and quantity semantics', (
    tester,
  ) async {
    final (store, _) = await setup([item('a', 'pork', quantity: '1 lb')]);
    await screen(tester, store);
    final semantics = tester.ensureSemantics();
    await tester.pump();
    final row = find.byKey(const ValueKey('a'));
    final tile = find.descendant(of: row, matching: find.byType(ListTile));
    expect(tester.getSize(tile).height, greaterThanOrEqualTo(48));
    try {
      expect(find.bySemanticsLabel(RegExp(r'1 lb pork')), findsOneWidget);
    } finally {
      semantics.dispose();
    }
    await tester.tapAt(tester.getTopLeft(tile) + const Offset(20, 24));
    await tester.pump();
    expect(store.shopping.single.checked, true);
    expect(
      tester.widget<Text>(find.text('1 lb pork')).style!.decoration,
      TextDecoration.lineThrough,
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a reversal cancels a pending move and reduced motion moves immediately',
    (tester) async {
      final (store, _) = await setup([item('a', 'Flour')]);
      await screen(tester, store);
      await tester.tap(find.text('Flour'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SnackBar), findsNothing);
      await store.editShopping(ShoppingEdit.check(ids: ['a'], checked: false));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      expect(store.shopping.single.checked, false);
      expect(find.text('Checked (1)'), findsNothing);
      expect(find.text('Flour'), findsOneWidget);
      await screen(tester, store, reduceMotion: true);
      await tester.tap(find.text('Flour'));
      await tester.pump();
      expect(find.text('Checked (1)'), findsOneWidget);
      expect(find.text('Flour'), findsNothing);
      await tester.tap(find.text('Checked (1)'));
      await tester.pump();
      expect(find.text('Flour'), findsOneWidget);
      await tester.tap(find.text('Flour'));
      await tester.pump();
      expect(find.text('Checked (1)'), findsNothing);
      expect(find.text('Flour'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'both bulk actions offer four-second Undo, clear confirmation and text saving',
    (tester) async {
      final (store, _) = await setup([item('a', 'Flour'), item('b', 'Salt')]);
      var saves = 0;
      await screen(
        tester,
        store,
        save: () async {
          saves++;
        },
      );
      await menu(tester, 'Check all');
      expect(store.shopping.every((i) => i.checked), true);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 4),
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.shopping.every((i) => !i.checked), true);
      await menu(tester, 'Check all');
      await menu(tester, 'Uncheck all');
      expect(store.shopping.every((i) => !i.checked), true);
      expect(
        tester.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 4),
      );
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.shopping.every((i) => i.checked), true);
      await menu(tester, 'Uncheck all');
      await tester.tap(find.text('Flour'));
      await tester.pumpAndSettle();
      await menu(tester, 'Clear checked');
      expect(store.shopping.single.name, 'Salt');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.shopping.length, 2);
      await menu(tester, 'Save list as text');
      expect(saves, 1);
      await menu(tester, 'Clear entire list');
      expect(find.text('Clear entire shopping list?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.shopping.length, 2);
      await menu(tester, 'Clear entire list');
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(store.shopping, isEmpty);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(store.shopping.length, 2);
    },
  );

  for (final state in ['empty', 'unchecked', 'checked', 'partial']) {
    testWidgets(
      'both bulk actions have correct enabled state for $state list',
      (tester) async {
        final (store, _) = await setup([
          if (state != 'empty') item('a', 'Flour', checked: state == 'checked'),
          if (state == 'partial') item('b', 'Salt', checked: true),
        ]);
        await screen(tester, store);
        await tester.tap(find.byTooltip('Shopping list options'));
        await tester.pumpAndSettle();
        final check = tester.widget<PopupMenuItem<String>>(
          find.widgetWithText(PopupMenuItem<String>, 'Check all'),
        );
        final uncheck = tester.widget<PopupMenuItem<String>>(
          find.widgetWithText(PopupMenuItem<String>, 'Uncheck all'),
        );
        expect(check.enabled, state == 'unchecked' || state == 'partial');
        expect(uncheck.enabled, state == 'checked' || state == 'partial');
        if (state == 'partial') {
          await tester.tap(find.text('Uncheck all'));
          await tester.pumpAndSettle();
          expect(store.shopping.every((i) => !i.checked), true);
          await tester.tap(find.text('Undo'));
          await tester.pumpAndSettle();
          expect(store.shopping.where((i) => i.checked).length, 1);
        } else {
          await tester.tapAt(const Offset(10, 400));
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('failed checks and removed or disposed moving rows stay safe', (
    tester,
  ) async {
    final (store, repo) = await setup([item('a', 'Flour')]);
    await screen(tester, store);
    repo.fail = true;
    await tester.tap(find.text('Flour'));
    await tester.pumpAndSettle();
    expect(find.text('Write failed.'), findsOneWidget);
    expect(store.shopping.single.checked, false);
    expect(find.text('Checked (1)'), findsNothing);
    repo.fail = false;
    await tester.tap(find.text('Flour'));
    await tester.pump();
    await tester.tap(find.text('Flour'));
    expect(repo.edits, 2);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 50));
    await store.editShopping(ShoppingEdit.remove(ids: ['a']));
    await tester.pump(const Duration(milliseconds: 600));
    expect(store.shopping, isEmpty);
    expect(find.text('Checked (1)'), findsNothing);
    await store.editShopping(const ShoppingEdit.addManual(text: 'Milk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Milk'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'long press and right click edit retain failure input and detach on save',
    (tester) async {
      final (store, repo) = await setup([
        item('a', 'Flour', quantity: '2 cups', sources: ['a']),
      ]);
      await screen(tester, store);
      await tester.longPress(find.text('2 cups Flour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      final edit = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Item',
      );
      await tester.enterText(edit, 'Bread flour');
      repo.fail = true;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Write failed.'), findsOneWidget);
      expect(tester.widget<TextField>(edit).controller!.text, 'Bread flour');
      expect(store.shopping.single.contributorIds, ['a']);
      repo.fail = false;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.shopping.single.name, 'Bread flour');
      expect(store.shopping.single.contributorIds, isEmpty);
      expect(find.byType(SnackBar), findsNothing);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Bread flour')),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit item'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'recipe ingredient selection preserves explicit indices, zero guard, failure and cancellation',
    (tester) async {
      final base = recipe('a');
      final source = Recipe(
        id: base.id,
        fields: RecipeFields(
          title: base.fields.title,
          description: '',
          servings: '',
          prepTime: '',
          cookTime: '',
          totalTime: '',
          source: '',
          tags: const [],
          notes: '',
          steps: const [],
          ingredients: [
            for (final name in ['Flour', 'Salt', 'Milk'])
              Ingredient(
                name: name,
                amount: const Amount.unspecified(),
                unit: '',
                prepNote: '',
                optional: false,
                section: '',
              ),
          ],
        ),
        favorite: false,
        createdAt: base.createdAt,
        updatedAt: base.updatedAt,
        revision: base.revision,
      );
      final (store, repo) = await setup([], recipes: [source]);
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showShoppingSelection(context, store, source),
                child: const Text('Select'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select none'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Add'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Salt'));
      await tester.pumpAndSettle();
      repo.fail = true;
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(repo.selected, [1]);
      expect(find.text('Write failed.'), findsOneWidget);
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Salt'),
            )
            .value,
        true,
      );
      repo.fail = false;
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(store.shopping.single.name, 'Salt');
      expect(find.text('Added to shopping list'), findsOneWidget);
      final confirmation = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(confirmation.duration, const Duration(seconds: 2));
      expect(confirmation.persist, isFalse);
      expect(confirmation.action, isNull);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.shopping.single.name, 'Salt');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320dp large text, long names, full width and disposed pending write',
    (tester) async {
      final (store, repo) = await setup([
        item(
          'a',
          'Very long shopping item name that wraps across multiple lines',
          quantity: '1/3 cup + 2 ounces',
          sources: ['a'],
        ),
      ]);
      await screen(tester, store, size: const Size(320, 780), scale: 1.5);
      expect(
        tester
            .getSize(find.byWidgetPredicate((w) => w is CustomScrollView))
            .width,
        320,
      );
      final label = find.byKey(const ValueKey('shopping-item-label-a'));
      final text = tester.widget<Text>(label);
      expect(
        text.textSpan!.toPlainText(),
        '1/3 cup + 2 ounces Very long shopping item name that wraps across multiple lines',
      );
      expect(text.maxLines, isNull);
      expect(text.overflow, isNull);
      expect(tester.getSize(label).height, greaterThan(48));
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.getBottomRight(input()).dy, lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
      await tester.enterText(input(), 'Milk');
      repo.gate = Completer<void>();
      await tester.tap(find.byTooltip('Add item'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
