import 'dart:async';

import 'package:cookdex/interaction_idle.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_search.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/interaction_idle_scope.dart';
import 'package:cookdex/update_checker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recipe_store_test.dart' show summary, FakeRepository;
import 'support/polish_fixtures.dart' show polishRecipe;
import 'sync_controller_test.dart' show FakeSyncBackend;
import 'update_checker_test.dart' show FakeReleaseSource;

void main() {
  testWidgets(
    'workload signals cover touch, drag, coast and settle without repetition',
    (tester) async {
      final changes = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: InteractionIdleScope(
            onScrollWorkload: changes.add,
            child: ListView.builder(
              itemExtent: 56,
              itemCount: 500,
              itemBuilder: (_, i) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Text('Recipe $i'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      changes.clear();
      final contact = await tester.startGesture(const Offset(200, 450));
      expect(changes, [true]);
      await contact.up();
      await tester.pump();
      expect(changes, [true, false]);
      changes.clear();
      await tester.fling(find.byType(ListView), const Offset(0, -350), 4000);
      expect(changes, [true, true, true]);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(changes, [true, true, true]);
      await tester.pumpAndSettle();
      expect(changes, [true, true, true, false]);
      await tester.fling(find.byType(ListView), const Offset(0, -350), 4000);
      await tester.pumpWidget(const SizedBox());
      expect(changes, [true, true, true, false, true, true, true, false]);
    },
  );

  testWidgets('coalesces work and rechecks contact before starting', (
    tester,
  ) async {
    final idle = InteractionIdle();
    final hold = Object(), key = Object();
    var runs = 0;
    idle.hold(hold, true);
    for (var n = 0; n < 20; n++) {
      idle.runWhenIdle(key, () => runs++);
    }
    await tester.pump(const Duration(milliseconds: 1));
    expect(runs, 0);
    idle.hold(hold, false);
    idle.hold(hold, true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(runs, 0);
    idle.hold(hold, false);
    await tester.pump(const Duration(milliseconds: 1));
    expect(runs, 1);
  });

  testWidgets(
    'holds through contact, fling, and unmounts without a stuck gate',
    (tester) async {
      final idle = InteractionIdle.instance;
      await tester.pumpWidget(
        MaterialApp(
          home: InteractionIdleScope(
            child: ListView.builder(
              itemExtent: 56,
              itemCount: 500,
              itemBuilder: (_, i) => Text('Recipe $i'),
            ),
          ),
        ),
      );
      final touch = await tester.startGesture(const Offset(200, 400));
      expect(idle.busy, isTrue);
      await touch.up();
      await tester.pump(const Duration(milliseconds: 1));
      expect(idle.busy, isFalse);
      await tester.fling(find.byType(ListView), const Offset(0, -350), 4000);
      await tester.pump(const Duration(milliseconds: 16));
      expect(idle.busy, isTrue);
      var ran = false;
      idle.runWhenIdle(Object(), () => ran = true);
      await tester.pump(const Duration(milliseconds: 16));
      expect(ran, isFalse);
      await tester.pumpAndSettle();
      expect(idle.busy, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(ran, isTrue);
      await tester.fling(find.byType(ListView), const Offset(0, -350), 4000);
      await tester.pumpWidget(const SizedBox());
      expect(idle.busy, isFalse);
    },
  );

  testWidgets('a search is complete while background indexing is held', (
    tester,
  ) async {
    final idle = InteractionIdle.instance, hold = Object();
    var warmed = 0, chunks = 0;
    final index = RecipeSearchIndex(() => warmed++);
    final rows = [
      for (var i = 0; i < 40; i++) summary(polishRecipe('$i', 'Lemon rice $i')),
    ];
    final prefs = LocalPreferences.memory()..query = 'lemon';
    idle.hold(hold, true);
    InteractionIdle.debugWork = (name, start) {
      if (start && name == 'search-index') chunks++;
    };
    try {
      for (final row in rows) {
        index.queue(row);
      }
      index.warm();
      await tester.pump(const Duration(milliseconds: 1));
      expect(chunks, 0);
      expect(warmed, 0);
      expect(index.rank(rows, prefs, picker: false).recipes, hasLength(40));
    } finally {
      index.dispose();
      prefs.dispose();
      InteractionIdle.debugWork = null;
      idle.hold(hold, false);
      await tester.pump(const Duration(milliseconds: 1));
    }
  });

  testWidgets('typing gets full results while initial preparation is held', (
    tester,
  ) async {
    final idle = InteractionIdle.instance, hold = Object();
    final prefs = LocalPreferences.memory()..query = 'rice';
    final store = RecipeStore(
      FakeRepository([
        polishRecipe('a', 'Lemon rice'),
        polishRecipe('b', 'Lemon beans'),
      ]),
      prefs,
    );
    await store.initialize(prepareSearchAfterPaint: true);
    idle.hold(hold, true);
    store.prepareRecipeSearch();
    await tester.pump(const Duration(milliseconds: 1));
    expect(store.preparingRecipeSearch, isTrue);
    prefs.setQuery('lemon');
    expect(store.preparingRecipeSearch, isFalse);
    expect(store.visibleRecipes, hasLength(2));
    store.dispose();
    prefs.dispose();
    idle.hold(hold, false);
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('sync polls wait but an in-progress poll may finish', (
    tester,
  ) async {
    final idle = InteractionIdle.instance, hold = Object();
    final backend = FakeSyncBackend();
    final sync = SyncController(
      backend: backend,
      refreshRecipes: () async {},
      isAndroid: true,
      requestPermission: () async => true,
    );
    idle.hold(hold, true);
    final pending = sync.refresh();
    await tester.pump(const Duration(milliseconds: 1));
    expect(backend.statusCalls, 0);
    idle.hold(hold, false);
    await tester.pump(const Duration(milliseconds: 1));
    await pending;
    expect(backend.statusCalls, 1);
    backend.statusGate = Completer();
    final active = sync.refresh();
    idle.hold(hold, true);
    backend.statusGate!.complete(backend.current);
    await active;
    expect(backend.statusCalls, 2);
    sync.dispose();
    idle.hold(hold, false);
  });

  testWidgets('update requests and reply handling wait for idle', (
    tester,
  ) async {
    final idle = InteractionIdle.instance, hold = Object();
    final source = FakeReleaseSource();
    final prefs = LocalPreferences.memory();
    final update = UpdateController(
      preferences: prefs,
      source: source,
      installedVersion: () async => '1.10.5',
    );
    idle.hold(hold, true);
    final check = update.check();
    await tester.pump(const Duration(milliseconds: 1));
    expect(source.calls, 0);
    source.pending = Completer();
    idle.hold(hold, false);
    await tester.pump(const Duration(milliseconds: 1));
    expect(source.calls, 1);
    idle.hold(hold, true);
    source.pending!.complete(source.result);
    await tester.pump(const Duration(milliseconds: 1));
    expect(update.state, UpdateCheckState.checking);
    idle.hold(hold, false);
    await tester.pump(const Duration(milliseconds: 1));
    await check;
    expect(update.state, UpdateCheckState.current);
    update.dispose();
    prefs.dispose();
  });
}
