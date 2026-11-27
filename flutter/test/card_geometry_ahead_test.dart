import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/prepared_card_title.dart';
import 'package:cookdex/ui/progressive_cards.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/performance/deep_fixture.dart';
import 'recipe_store_test.dart' show summary;

RecipeSummary _recipe(int index) => summary(
  Recipe(
    id: '$index',
    favorite: false,
    revision: 1,
    createdAt: '2026-10-30',
    updatedAt: '2026-10-30',
    fields: scaleRecipeFields(index),
  ),
);

List<double> _dimensions(CardGeometry value) => [
  value.height,
  value.titleHeight,
  value.descriptionHeight,
  value.metadataHeight,
  value.tagsHeight,
];

void main() {
  testWidgets('reversing prepared windows does not refresh unchanged titles', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final cache = CardGeometryCache()..configure(context, 358);
    addTearDown(cache.clear);
    final recipes = List.generate(112, _recipe);
    final values = recipes.map(cache.measurePrepared).toList();
    final titles = values.map((value) => value!.title).toList();
    expect(titles.every((title) => title != null), isTrue);
    // Two overlapping 48-card ahead windows and 32 other retained cards.
    // All numeric sizes already exist, just as in the warm drag recording.
    for (var pass = 0; pass < 8; pass++) {
      final indices = pass.isEven
          ? List.generate(48, (index) => index)
          : List.generate(48, (index) => 79 - index);
      for (final index in [...indices, ...List.generate(32, (i) => i + 80)]) {
        expect(cache.needsPreparation(recipes[index]), isFalse);
        final value = cache.measurePrepared(recipes[index]);
        expect(value, same(values[index]));
        expect(value!.title, same(titles[index]));
      }
    }
  });

  testWidgets('partial preparation drains to synchronous geometry', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: cookdexTheme(),
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final ahead = CardGeometryCache()..configure(context, 358);
    final synchronous = CardGeometryCache()..configure(context, 358);
    addTearDown(ahead.clear);
    addTearDown(synchronous.clear);
    for (var index = 0; index < 3; index++) {
      final recipe = _recipe(index);
      expect(ahead.prepareStep(recipe), isFalse);
      expect(ahead.contains(recipe), isFalse);
      final actual = ahead.measurePrepared(recipe)!;
      expect(ahead.lastHit, isFalse);
      final expected = synchronous.measurePrepared(recipe)!;
      expect(_dimensions(actual), _dimensions(expected));
      expect(actual.title!.painter.size, expected.title!.painter.size);
      expect(ahead.measurePrepared(recipe), same(actual));
      expect(ahead.lastHit, isTrue);
    }
    final recipe = _recipe(3);
    var steps = 0;
    while (!ahead.prepareStep(recipe)) {
      expect(++steps, lessThan(100));
    }
    expect(ahead.contains(recipe), isTrue);
    final actual = ahead.measurePrepared(recipe)!;
    expect(ahead.lastHit, isTrue);
    expect(
      _dimensions(actual),
      _dimensions(synchronous.measurePrepared(recipe)!),
    );
  });

  testWidgets(
    'ahead refresh preserves numeric geometry and a mounted evicted title',
    (tester) async {
      late BuildContext context;
      PreparedTitle? mountedTitle;
      var titleWidth = 286.0;
      final recipes = List.generate(
        CardGeometryCache.titleCapacity + 6,
        _recipe,
      );
      Future<void> host() => tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Builder(
            builder: (value) {
              context = value;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: titleWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (mountedTitle case final title?)
                        PreparedCardTitle(recipes.first.title, prepared: title),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      await host();
      final cache = CardGeometryCache()..configure(context, 358);
      addTearDown(cache.clear);
      expect(cache.needsPreparation(recipes.first), isTrue);
      final first = cache.measurePrepared(recipes.first)!;
      mountedTitle = first.title!;
      final originalTitle = mountedTitle;
      final titleSize = originalTitle.painter.size;
      await host();
      final bounds = tester.getRect(find.text(recipes.first.title));
      final values = [first];
      for (final recipe in recipes.skip(1)) {
        values.add(cache.measurePrepared(recipe)!);
      }
      final dimensions = values.map(_dimensions).toList();
      expect(first.title, isNull);
      expect(cache.contains(recipes.first), isTrue);
      expect(cache.needsPreparation(recipes.first), isTrue);
      expect(cache.prepareStep(recipes.first), isTrue);
      final refreshed = first.title!;
      expect(refreshed, isNot(same(originalTitle)));
      expect(refreshed.painter.size, titleSize);
      expect(cache.needsPreparation(recipes.first), isFalse);
      expect(cache.prepareStep(recipes.first), isTrue);
      expect(first.title, same(refreshed));

      // Repeated warm passes must refresh paragraphs without replacing sizes
      // or growing the bounded cache, including after a refreshed title evicts.
      for (var pass = 0; pass < 2; pass++) {
        for (var index = 0; index < recipes.length; index++) {
          expect(cache.prepareStep(recipes[index]), isTrue);
          expect(cache.needsPreparation(recipes[index]), isFalse);
          expect(cache.measurePrepared(recipes[index]), same(values[index]));
          expect(cache.lastHit, isTrue);
          expect(_dimensions(values[index]), dimensions[index]);
          expect(
            values.where((value) => value.title != null),
            hasLength(CardGeometryCache.titleCapacity),
          );
        }
      }
      expect(first.title, isNull);
      // Force the mounted old paragraph through fallback layout and back after
      // both its original and replacement cache entries have been evicted.
      titleWidth = 200;
      await host();
      expect(tester.takeException(), isNull);
      titleWidth = 286;
      await host();
      expect(tester.getRect(find.text(recipes.first.title)), bounds);
      expect(originalTitle.painter.size, titleSize);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'title eviction retains geometry; width and scaler invalidate it',
    (tester) async {
      late BuildContext context;
      Future<void> host(double scale) => tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Builder(
              builder: (value) {
                context = value;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await host(1);
      final cache = CardGeometryCache()..configure(context, 358);
      addTearDown(cache.clear);
      final recipes = List.generate(
        CardGeometryCache.titleCapacity + 6,
        _recipe,
      );
      final first = cache.measurePrepared(recipes.first)!;
      final dimensions = _dimensions(first);
      expect(first.title, isNotNull);
      final values = <CardGeometry>[first];
      for (final recipe in recipes.skip(1)) {
        values.add(cache.measurePrepared(recipe)!);
      }
      expect(
        values.where((value) => value.title != null),
        hasLength(CardGeometryCache.titleCapacity),
      );
      expect(first.title, isNull);
      expect(cache.contains(recipes.first), isTrue);
      expect(cache.measurePrepared(recipes.first), same(first));
      expect(cache.lastHit, isTrue);
      expect(_dimensions(first), dimensions);

      cache.configure(context, 300);
      expect(cache.contains(recipes.first), isFalse);
      final narrower = cache.measurePrepared(recipes.first)!;
      expect(cache.lastHit, isFalse);
      expect(narrower, isNot(same(first)));
      expect(narrower.title!.maxWidth, 228);
      expect(values.every((value) => value.title == null), isTrue);

      // An unfinished job must also be discarded with its old environment.
      expect(cache.prepareStep(recipes[1]), isFalse);
      await host(2);
      cache.configure(context, 300);
      expect(cache.contains(recipes.first), isFalse);
      expect(narrower.title, isNull);
      final larger = cache.measurePrepared(recipes.first)!;
      expect(cache.lastHit, isFalse);
      expect(larger.titleHeight, greaterThan(narrower.titleHeight));
      final fresh = CardGeometryCache()..configure(context, 300);
      addTearDown(fresh.clear);
      expect(
        _dimensions(cache.measurePrepared(recipes[1])!),
        _dimensions(fresh.measurePrepared(recipes[1])!),
      );
    },
  );
}
