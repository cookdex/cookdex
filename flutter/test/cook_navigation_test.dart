import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

Recipe _recipe() => Recipe(
  id: 'cook-navigation-fixture',
  favorite: false,
  createdAt: '2026-01-01',
  updatedAt: '2026-01-01',
  revision: 1,
  fields: RecipeFields(
    title: 'Synthetic soup',
    description: '',
    servings: '',
    prepTime: '',
    cookTime: '',
    totalTime: '',
    source: '',
    tags: const [],
    notes: '',
    ingredients: const [],
    steps: List.generate(13, (index) => 'Synthetic step ${index + 1}'),
  ),
);

Future<CookController> _mount(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  double recipeScale = 1,
  double bottomInset = 28,
  bool includeBottomInset = true,
}) async {
  final size = Size(width, 760);
  await tester.binding.setSurfaceSize(size);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final preferences = LocalPreferences.memory();
  final cook = CookController(preferences: preferences, setWake: (_) async {})
    ..setRecipe(_recipe())
    ..toggle();
  addTearDown(() {
    cook.dispose();
    preferences.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: RecipeTextScaler(TextScaler.linear(scale), recipeScale),
          padding: EdgeInsets.only(bottom: bottomInset),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: CookNavigation(
            cook: cook,
            includeBottomInset: includeBottomInset,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 200));
  return cook;
}

void main() {
  testWidgets('kitchen buttons show arrows and bounded progress through Done', (
    tester,
  ) async {
    final cook = await _mount(tester, width: 600);
    final previous = find.widgetWithText(OutlinedButton, 'Previous');
    final next = find.widgetWithText(FilledButton, 'Next');
    expect(tester.widget<OutlinedButton>(previous).onPressed, isNull);
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);
    expect(find.text('Step 1 of 13'), findsOneWidget);
    expect(
      find.descendant(of: previous, matching: find.byIcon(Symbols.arrow_back)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: next, matching: find.byIcon(Symbols.arrow_forward)),
      findsOneWidget,
    );
    expect(tester.getSize(previous).height, greaterThanOrEqualTo(56));
    expect(tester.getSize(next).height, greaterThanOrEqualTo(56));
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(cook.step, 1);
    expect(find.text('Step 2 of 13'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(previous).onPressed, isNotNull);
    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(cook.step, 0);
    cook.selectStep(8);
    await tester.pumpAndSettle();
    expect(find.text('Step 9 of 13'), findsOneWidget);
    cook.selectStep(12);
    await tester.pumpAndSettle();
    expect(find.text('Next'), findsNothing);
    expect(find.text('Step 13 of 13'), findsOneWidget);
    final done = find.widgetWithText(FilledButton, 'Done');
    expect(tester.widget<FilledButton>(done).onPressed, isNotNull);
    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(cook.active, isFalse);
    expect(cook.step, 12);
    expect(cook.preferences.cookStep('cook-navigation-fixture'), 12);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 600.0, 364.0]) {
    testWidgets('Cook footer clears the gesture inset at $width dp', (
      tester,
    ) async {
      await _mount(tester, width: width);
      final footer = tester.getRect(find.byType(CookNavigation));
      final previous = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Previous'),
      );
      final next = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
      expect(footer.bottom, 760);
      expect(previous.bottom, lessThanOrEqualTo(760 - 28));
      expect(next.bottom, lessThanOrEqualTo(760 - 28));
      expect(previous.left, greaterThanOrEqualTo(12));
      expect(next.right, lessThanOrEqualTo(width - 12));
      final card = tester.getRect(find.byKey(const Key('cook-controls-card')));
      expect(card.left, 8);
      expect(card.right, width - 8);
      expect(card.bottom, lessThanOrEqualTo(760 - 28 - 8));
      expect(
        tester
            .widget<Material>(find.byKey(const Key('cook-controls-card')))
            .borderRadius,
        BorderRadius.circular(16),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shell can own the inset under compact Cook controls', (
    tester,
  ) async {
    await _mount(tester, includeBottomInset: false);
    final next = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
    expect(next.bottom, greaterThan(760 - 28));
    final safeArea = find.descendant(
      of: find.byType(CookNavigation),
      matching: find.byType(SafeArea),
    );
    expect(tester.widget<SafeArea>(safeArea).bottom, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 364.0]) {
    for (final scale in [2.0, 3.0]) {
      testWidgets(
        'Cook keeps one-line labels at $width dp and $scale system text',
        (tester) async {
          final cook = await _mount(tester, width: width, scale: scale);
          final previous = find.byKey(const Key('cook-previous'));
          final previousLabel = find.byKey(const Key('cook-previous-label'));
          final next = find.widgetWithText(FilledButton, 'Next');
          final progress = tester.getRect(find.text('1/13'));
          expect(progress.bottom, lessThan(tester.getRect(previous).top));
          expect(previousLabel.hitTestable(), findsOneWidget);
          expect(next.hitTestable(), findsOneWidget);
          expect(tester.getSize(previous).height, greaterThanOrEqualTo(56));
          expect(tester.getSize(next).height, greaterThanOrEqualTo(56));
          expect(tester.getRect(next).bottom, lessThanOrEqualTo(760 - 28));
          final previousText = tester.widget<Text>(previousLabel);
          expect(previousText.maxLines, 1);
          expect(previousText.softWrap, false);
          // Labels keep the requested system scale, with enough width to paint
          // the full single line (no clipping/ellipsis/fit-to-width shrinking).
          final textContext = tester.element(previousLabel);
          expect(MediaQuery.textScalerOf(textContext).scale(16), 16 * scale);
          final measured = TextPainter(
            text: TextSpan(
              text: previousText.data,
              style: DefaultTextStyle.of(textContext).style,
            ),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(textContext),
          )..layout();
          expect(
            tester.getSize(previousLabel).width,
            greaterThanOrEqualTo(measured.width),
          );
          measured.dispose();
          await tester.tap(next);
          await tester.pumpAndSettle();
          expect(cook.step, 1);
          cook.selectStep(12);
          await tester.pumpAndSettle();
          expect(find.text('Done').hitTestable(), findsOneWidget);
          await tester.tap(find.widgetWithText(FilledButton, 'Done'));
          await tester.pumpAndSettle();
          expect(cook.active, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('recipe Extra large does not enlarge Cook controls', (
    tester,
  ) async {
    await _mount(tester, recipeScale: 1);
    final original = tester.getSize(find.text('Previous'));
    await _mount(tester, recipeScale: 1.3);
    expect(tester.getSize(find.text('Previous')), original);
    final context = tester.element(find.text('Previous'));
    expect(MediaQuery.textScalerOf(context).scale(16), 16);
    expect(tester.takeException(), isNull);
  });

  testWidgets('counter shortens before buttons leave a single row', (
    tester,
  ) async {
    await _mount(tester, width: 460);
    expect(find.text('1/13'), findsOneWidget);
    final previous = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Previous'),
    );
    final next = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
    final counter = tester.getRect(find.text('1/13'));
    expect(previous.top, next.top);
    expect(counter.center.dy, closeTo(previous.center.dy, 1));
    expect(tester.takeException(), isNull);
  });
}
