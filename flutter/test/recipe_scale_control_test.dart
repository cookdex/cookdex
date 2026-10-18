import 'package:cookdex/ui/recipe_scale_control.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(320, 800),
    const Size(412, 892),
    const Size(1280, 800),
  ]) {
    for (final font in [1.0, 2.0]) {
      testWidgets(
        'scale picker fits $size at font $font and dismisses safely',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final navigator = GlobalKey<NavigatorState>();
          var scale = 2;
          var outsideActions = 0;
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: navigator,
              theme: cookdexTheme(),
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, update) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: RecipeScaleControl(
                            scale: scale,
                            textScaler: TextScaler.linear(font),
                            onSelected: (value) => update(() => scale = value),
                            heading: Text(
                              'Ingredients',
                              textScaler: TextScaler.linear(font * 1.3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 100),
                        TextButton(
                          onPressed: () => outsideActions++,
                          child: const Text('Outside'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
          final toggle = find.byKey(const Key('recipe-scale-toggle'));
          final options = find.byKey(const Key('recipe-scale-options'));
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('recipe-scale-2')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          // Scroll all the way across the row and choose the farthest option.
          await tester.drag(options, const Offset(-2000, 0));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('recipe-scale-10')));
          await tester.pumpAndSettle();
          expect(scale, 10);
          expect(
            find.byKey(const Key('recipe-scale-10')).hitTestable(),
            findsNothing,
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          // Reopening must bring the current selection into view.
          expect(
            find.byKey(const Key('recipe-scale-10')).hitTestable(),
            findsOneWidget,
          );
          await navigator.currentState!.maybePop();
          await tester.pumpAndSettle();
          expect(toggle, findsOneWidget);
          expect(scale, 10);
          expect(
            find.byKey(const Key('recipe-scale-10')).hitTestable(),
            findsNothing,
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Outside'));
          expect(outsideActions, 0);
          await tester.pumpAndSettle();
          expect(scale, 10);
          expect(
            find.byKey(const Key('recipe-scale-10')).hitTestable(),
            findsNothing,
          );
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          await tester.drag(options, const Offset(2000, 0));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('recipe-scale-1')));
          await tester.pumpAndSettle();
          expect(scale, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
