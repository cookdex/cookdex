import 'package:cookdex/ui/recipe_metadata.dart';
import 'package:cookdex/yield_presentation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Future<void> _metadata(
  WidgetTester tester, {
  String total = '',
  String prep = '',
  String cook = '',
  bool all = false,
  String servings = 'makes 2 large loaves',
  bool singleLine = false,
  double width = 800,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: SizedBox(
          width: width,
          child: RecipeMetadata(
            servings: servings,
            totalTime: total,
            prepTime: prep,
            cookTime: cook,
            showAllTimes: all,
            singleLine: singleLine,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('serving counts and ranges receive concise display text', () {
    for (final (raw, expected) in [
      ('6', '6'),
      ('6 servings', '6'),
      ('Serves 4-6', '4–6'),
      ('  SERVES 4 – 6  ', '4–6'),
      ('1 serving', '1'),
      ('½', '½'),
      ('1½ servings', '1½'),
      ('Serves 1½-2½', '1½–2½'),
      ('Makes 4 servings', '4'),
      ('Makes 5–6 servings', '5–6'),
      ('2 1/2 servings', '2 1/2'),
      ('Serves 2 to 4', '2–4'),
    ]) {
      final shown = presentRecipeYield(raw);
      expect(shown.isServings, isTrue, reason: raw);
      expect(shown.text, expected, reason: raw);
    }
  });

  test('other yields retain meaning and only lose leading Makes', () {
    for (final (raw, expected) in [
      ('Makes 2 large loaves', '2 large loaves'),
      ('mAkEs 12 cookies', '12 cookies'),
      ('2 jars (500 ml each)', '2 jars (500 ml each)'),
      ('1 pan, serves about 6', '1 pan, serves about 6'),
      ('Makeshift supper', 'Makeshift supper'),
    ]) {
      final shown = presentRecipeYield(raw);
      expect(shown.isServings, isFalse, reason: raw);
      expect(shown.text, expected, reason: raw);
    }
  });

  testWidgets('servings and yields have distinct icons and semantic labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _metadata(tester, servings: 'Serves 4-6');
    expect(find.byIcon(Symbols.group), findsOneWidget);
    expect(find.byIcon(Symbols.inventory_2), findsNothing);
    expect(find.text('4–6'), findsOneWidget);
    expect(find.bySemanticsLabel('Servings: 4–6'), findsOneWidget);
    await _metadata(tester);
    expect(find.byIcon(Symbols.inventory_2), findsOneWidget);
    expect(find.byIcon(Symbols.group), findsNothing);
    expect(find.bySemanticsLabel('Yield: 2 large loaves'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('grid metadata stays one scaled row with full accessible text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const yieldText = '12 very large jars of preserved synthetic fruit';
    const time = '2 hours plus an overnight rest';
    await _metadata(
      tester,
      servings: 'Makes $yieldText',
      total: time,
      singleLine: true,
      width: 180,
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    final metadata = find.byType(RecipeMetadata);
    final context = tester.element(metadata);
    expect(tester.getSize(metadata).height, recipeMetadataLineHeight(context));
    for (final text in tester.widgetList<Text>(
      find.descendant(of: metadata, matching: find.byType(Text)),
    )) {
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.softWrap, isFalse);
    }
    expect(find.bySemanticsLabel('Yield: $yieldText'), findsOneWidget);
    expect(find.bySemanticsLabel('Total time: $time'), findsOneWidget);
    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
    expect(
      tooltips.map((t) => t.message),
      containsAll(['Yield: $yieldText', 'Total time: $time']),
    );
    final scaledHeight = tester.getSize(metadata).height;
    await _metadata(tester, singleLine: true, width: 180);
    expect(tester.getSize(metadata).height, lessThan(scaledHeight));
    semantics.dispose();
  });

  testWidgets('normal metadata can wrap long yields on narrow screens', (
    tester,
  ) async {
    await _metadata(
      tester,
      width: 180,
      textScale: 2,
      servings: 'Makes 12 very large jars of preserved synthetic fruit',
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(RecipeMetadata)).height,
      greaterThan(
        recipeMetadataLineHeight(tester.element(find.byType(RecipeMetadata))),
      ),
    );
    final text = tester.widget<Text>(
      find.text('12 very large jars of preserved synthetic fruit'),
    );
    expect(text.maxLines, isNull);
  });

  testWidgets('cards show entered total alone when available', (tester) async {
    await _metadata(
      tester,
      total: ' 1 hr + resting ',
      prep: '15 min',
      cook: '45 min',
    );
    expect(find.text(' 1 hr + resting '), findsOneWidget);
    expect(find.text('2 large loaves'), findsOneWidget);
    expect(find.textContaining('Prep'), findsNothing);
    expect(find.textContaining('Cook'), findsNothing);
    expect(find.textContaining('Total'), findsNothing);
  });

  testWidgets('prep and cook are labeled including a single time', (
    tester,
  ) async {
    await _metadata(tester, prep: ' about 10 min ');
    expect(find.text('Prep  about 10 min '), findsOneWidget);
    await _metadata(tester, cook: '20–25 min');
    expect(find.text('Cook 20–25 min'), findsOneWidget);
    await _metadata(tester, prep: '10 min', cook: '20 min');
    expect(find.text('Prep 10 min'), findsOneWidget);
    expect(find.text('Cook 20 min'), findsOneWidget);
  });

  testWidgets('detail labels total when shown beside another time', (
    tester,
  ) async {
    await _metadata(
      tester,
      total: '30 min',
      prep: '10 min',
      cook: '20 min',
      all: true,
    );
    expect(find.text('Prep 10 min'), findsOneWidget);
    expect(find.text('Cook 20 min'), findsOneWidget);
    expect(find.text('Total 30 min'), findsOneWidget);
    await _metadata(tester, total: 'overnight', all: true);
    expect(find.text('overnight'), findsOneWidget);
    expect(find.textContaining('Total'), findsNothing);
  });

  testWidgets('semantic time labels keep their field meaning', (tester) async {
    final semantics = tester.ensureSemantics();
    await _metadata(
      tester,
      total: '30 min',
      prep: '10 min',
      cook: '20 min',
      all: true,
    );
    expect(find.bySemanticsLabel('Prep time: 10 min'), findsOneWidget);
    expect(find.bySemanticsLabel('Cook time: 20 min'), findsOneWidget);
    expect(find.bySemanticsLabel('Total time: 30 min'), findsOneWidget);
    semantics.dispose();
  });
}
