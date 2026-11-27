import 'package:cookdex/ui/prepared_compact_text.dart';
import 'package:cookdex/ui/prepared_card_title.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/interaction_idle.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'compact_preparation_test.dart' show mount;

void main() {
  testWidgets(
    'Compact text prepares at rest and does no paragraph work during a fling',
    (tester) async {
      final (_, controller, _) = await mount(tester);
      final work = tester
          .widget<PreparedCompactText>(find.byType(PreparedCompactText))
          .work;
      expect(
        work.cachedRecipes,
        inInclusiveRange(1, CompactTextPreparation.capacity),
      );
      controller.jumpTo(5000);
      await tester.pumpAndSettle();
      final count = work.preparedParagraphs;
      await tester.fling(
        find.byKey(const PageStorageKey('recipes-scroll')),
        const Offset(0, -500),
        5000,
      );
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        expect(controller.position.isScrollingNotifier.value, isTrue);
        expect(work.preparedParagraphs, count);
      }
      await tester.pumpAndSettle();
      expect(work.preparedParagraphs, greaterThan(count));
      expect(work.cachedRecipes, lessThanOrEqualTo(128));
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'Compact text holds while a finger is down, resumes and stays bounded across reversals',
    (tester) async {
      final (_, controller, _) = await mount(tester);
      final work = tester
          .widget<PreparedCompactText>(find.byType(PreparedCompactText))
          .work;
      final finger = await tester.startGesture(const Offset(180, 400));
      controller.jumpTo(8000);
      await tester.pump();
      final count = work.preparedParagraphs;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(work.preparedParagraphs, count);
      await finger.cancel();
      await tester.pumpAndSettle();
      expect(work.preparedParagraphs, greaterThan(count));
      for (final offset in [12000.0, 4000.0, 16000.0, 0.0]) {
        controller.jumpTo(offset);
        await tester.pumpAndSettle();
        expect(work.cachedRecipes, lessThanOrEqualTo(128));
      }
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'Compact paragraph environment invalidates and mounted leases remain safe',
    (tester) async {
      final (_, controller, _) = await mount(tester);
      final work = tester
          .widget<PreparedCompactText>(find.byType(PreparedCompactText))
          .work;
      controller.jumpTo(1000);
      await tester.pumpAndSettle();
      expect(find.byType(PreparedCardTitle, skipOffstage: false), findsWidgets);
      final before = work.revision;
      tester.view.physicalSize = const Size(320, 844);
      await tester.pumpAndSettle();
      expect(work.revision, greaterThan(before));
      final widthRevision = work.revision;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(work.revision, greaterThan(widthRevision));
      final store = tester
          .widget<RecipesScreen>(find.byType(RecipesScreen))
          .store;
      final old = store.visibleRecipes[40];
      while (work.pending) {
        work.prepareNext();
      }
      await store.toggleFavorite(old.id);
      await tester.pumpAndSettle();
      expect(work.lookup(old), isNull);
      expect(work.cachedRecipes, lessThanOrEqualTo(128));
      expect(tester.takeException(), isNull);
    },
    semanticsEnabled: false,
  );

  testWidgets(
    'Off-list interaction also holds preparation and wakes it once idle',
    (tester) async {
      final (_, controller, _) = await mount(tester);
      final work = tester
          .widget<PreparedCompactText>(find.byType(PreparedCompactText))
          .work;
      final owner = Object();
      addTearDown(() => InteractionIdle.instance.hold(owner, false));
      InteractionIdle.instance.hold(owner, true);
      controller.jumpTo(9000);
      await tester.pump();
      final count = work.preparedParagraphs;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(work.preparedParagraphs, count);
      InteractionIdle.instance.hold(owner, false);
      await tester.pumpAndSettle();
      expect(work.preparedParagraphs, greaterThan(count));
    },
    semanticsEnabled: false,
  );

  testWidgets('Oversized tag collections keep the native Text fallback', (
    tester,
  ) async {
    final work = CompactTextPreparation();
    addTearDown(work.dispose);
    final summary = RecipeSummary(
      id: 'large-tags',
      title: 'Soup',
      description: '',
      ingredients: const [],
      tags: List.generate(10000, (i) => 'Tag $i'),
      notes: '',
      favorite: false,
      createdAt: '',
      updatedAt: '',
      servings: '',
      prepTime: '',
      cookTime: '',
      totalTime: '',
      revision: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            work.configure(context, [summary], 240);
            return const SizedBox();
          },
        ),
      ),
    );
    work.prepareNext();
    expect(work.lookup(summary)!.tags, isNull);
    expect(work.lookup(summary)!.tagLabel, isEmpty);
    expect(work.preparedParagraphs, 1);
  });
}
