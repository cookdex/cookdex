import 'package:cookdex/ui/idle_build_ahead.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/recipe_grid.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show FakeRepository, recipe;

class _Row extends StatefulWidget {
  const _Row(this.index, this.created, this.disposed);
  final int index;
  final Set<int> created, disposed;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  void initState() {
    super.initState();
    widget.created.add(widget.index);
  }

  @override
  void dispose() {
    widget.disposed.add(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 100, child: Text('Row ${widget.index}'));
}

void main() {
  testWidgets('navigation pause cancels queued preparation and can resume', (
    tester,
  ) async {
    final paused = ValueNotifier(false);
    final created = <int>{}, disposed = <int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdleBuildAhead(
            paused: paused,
            builder: (context, cache) => ListView.builder(
              scrollCacheExtent: ScrollCacheExtent.pixels(cache),
              itemCount: 500,
              itemBuilder: (_, index) => _Row(index, created, disposed),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    paused.value = true;
    final before = created.length;
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(created.length, before);
    paused.value = false;
    await tester.pumpAndSettle();
    expect(created.length, greaterThan(before));
    await tester.pumpWidget(const SizedBox.shrink());
    paused.dispose();
  });

  testWidgets('idle card expansion leaves existing rows built', (tester) async {
    final prefs = LocalPreferences.memory();
    final store = RecipeStore(
      FakeRepository([for (var i = 0; i < 500; i++) recipe('$i')]),
      prefs,
    );
    await store.initialize();
    addTearDown(() async {
      debugOnRebuildDirtyWidget = null;
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      prefs.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipesScreen(
            store: store,
            preferences: prefs,
            onOpenRecipe: (_) {},
            onAdd: () {},
            onActions: (_) {},
          ),
        ),
      ),
    );
    final firstRows = find
        .byType(RecipeGridRow, skipOffstage: false)
        .evaluate()
        .toSet();
    expect(firstRows, isNotEmpty);
    var rebuilds = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (builtOnce && firstRows.contains(element)) rebuilds++;
    };
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      find.byType(RecipeGridRow, skipOffstage: false).evaluate().length,
      greaterThan(firstRows.length),
    );
    expect(rebuilds, 0);
    debugOnRebuildDirtyWidget = null;
    await tester.pumpAndSettle();
  });

  for (final all in [true, false]) {
    testWidgets(
      all
          ? 'visible first, bounded batches, retained editor rows'
          : 'Cards cache stays bounded across a 500 row library',
      (tester) async {
        final created = <int>{}, disposed = <int>{};
        final controller = ScrollController();
        final budget = all ? null : BuiltRowBudget(32);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IdleBuildAhead(
                allRows: all,
                builder: (context, cache) => ListView.builder(
                  controller: controller,
                  scrollCacheExtent: ScrollCacheExtent.pixels(cache),
                  itemCount: all ? 80 : 500,
                  itemBuilder: (_, index) => KeepBuilt(
                    key: ValueKey(index),
                    budget: budget,
                    child: _Row(index, created, disposed),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(created.length, lessThan(20));
        for (var frame = 0; frame < 10; frame++) {
          final before = created.length;
          await tester.pump(const Duration(milliseconds: 16));
          expect(created.length - before, lessThanOrEqualTo(2));
        }
        // Scroll before preparation completes: visible rows still build on demand.
        controller.jumpTo(3000);
        await tester.pump();
        expect(find.text('Row 31'), findsOneWidget);
        await tester.pumpAndSettle();
        if (all) {
          expect(created.length, 80);
          expect(find.byType(_Row, skipOffstage: false), findsNWidgets(80));
          final disposedBeforeReturn = Set<int>.of(disposed);
          controller.jumpTo(0);
          await tester.pumpAndSettle();
          expect(disposed, disposedBeforeReturn);
        } else {
          for (final offset in [10000.0, 20000.0, 30000.0]) {
            controller.jumpTo(offset);
            await tester.pumpAndSettle();
          }
          expect(created.length, greaterThan(60));
          expect(created.difference(disposed).length, lessThanOrEqualTo(40));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
