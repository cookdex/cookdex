import 'dart:ui' as ui;

import 'package:cookdex/ui/navigation_feedback.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduced = false}) => MaterialApp(
  theme: cookdexTheme().copyWith(platform: TargetPlatform.android),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: child!,
  ),
  home: Scaffold(body: child),
);

Future<void> _backGesture(
  WidgetTester tester,
  String method, {
  double? progress,
  double y = 300,
}) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall(
        method,
        progress == null
            ? null
            : <String, dynamic>{
                'touchOffset': <double>[5 + 250 * progress, y],
                'progress': progress,
                'swipeEdge': 0,
              },
      ),
    ),
    (_) {},
  );
  await tester.pump();
}

Future<Color> _pixel(WidgetTester tester, int x, int y) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('route-preview')),
  );
  final result = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final width = image.width;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return (data!.buffer.asUint8List(), width);
  });
  final (Uint8List data, int width) = result!;
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    data[offset + 3],
    data[offset],
    data[offset + 1],
    data[offset + 2],
  );
}

void main() {
  for (final width in [320.0, 390.0]) {
    for (final guarded in [false, true]) {
      testWidgets(
        'opaque page follows predictive Back and cancel at $width, guard=$guarded',
        (tester) async {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          const origin = Color(0xffd340a0);
          final surface = cookdexTheme().scaffoldBackgroundColor;
          late BuildContext routeContext;
          var backRequests = 0;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('route-preview'),
              child: MaterialApp(
                theme: cookdexTheme().copyWith(
                  platform: TargetPlatform.android,
                ),
                home: Scaffold(
                  backgroundColor: origin,
                  body: Builder(
                    builder: (context) {
                      routeContext = context;
                      return const Text('Origin');
                    },
                  ),
                ),
              ),
            ),
          );
          // Like RecipeDetail, this page has no Scaffold or painted background.
          const content = Column(
            key: Key('outgoing-page'),
            children: [
              Text('Detail'),
              Expanded(child: SizedBox()),
            ],
          );
          final route = cookdexRoute<void>(
            routeContext,
            builder: (_) => guarded
                ? PredictiveFormBackGuard(
                    enabled: true,
                    onBack: () => backRequests++,
                    child: const PopScope(canPop: false, child: content),
                  )
                : content,
          );
          Navigator.of(routeContext).push(route);
          await tester.pumpAndSettle();
          expect(await _pixel(tester, width ~/ 2, 400), surface);

          await _backGesture(tester, 'startBackGesture', progress: 0);
          for (final progress in [.25, .65]) {
            await _backGesture(
              tester,
              'updateBackGestureProgress',
              progress: progress,
              y: 360,
            );
            final page = tester.getRect(find.byKey(const Key('outgoing-page')));
            expect(page.left, greaterThan(0));
            expect(page.width, lessThan(width));
            expect(page.width, greaterThan(width * .9));
            expect(page.top, greaterThan(0));
            final clip = tester.widget<ClipRRect>(
              find.ancestor(
                of: find.byKey(const Key('outgoing-page')),
                matching: find.byType(ClipRRect),
              ),
            );
            expect(clip.borderRadius, isNot(BorderRadius.zero));
            // The origin peeks around the surface, never through blank content.
            expect(await _pixel(tester, 1, 400), origin);
            expect(await _pixel(tester, width ~/ 2, 400), surface);
          }
          await _backGesture(tester, 'cancelBackGesture');
          await tester.pumpAndSettle();
          expect(route.isCurrent, true);
          expect(backRequests, 0);
          expect(
            tester.getRect(find.byKey(const Key('outgoing-page'))),
            Rect.fromLTWH(0, 0, width, 800),
          );
          expect(await _pixel(tester, 1, 400), surface);

          await _backGesture(tester, 'startBackGesture', progress: 0);
          await _backGesture(tester, 'updateBackGestureProgress', progress: .4);
          await _backGesture(tester, 'commitBackGesture');
          await tester.pumpAndSettle();
          if (guarded) {
            expect(backRequests, 1);
            expect(route.isCurrent, true);
            expect(await _pixel(tester, 1, 400), surface);
          } else {
            expect(find.text('Detail'), findsNothing);
            expect(await _pixel(tester, width ~/ 2, 400), origin);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'FAB retains its element, blocks hidden taps and reverses smoothly',
    (tester) async {
      var visible = true;
      var taps = 0;
      late StateSetter update;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Center(
                child: ScrollAwareFab(
                  visible: visible,
                  child: FloatingActionButton(
                    key: const Key('fab'),
                    onPressed: () => taps++,
                    child: const Text('+'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final element = tester.element(find.byKey(const Key('fab')));
      update(() => visible = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final scale = tester.widget<ScaleTransition>(
        find.descendant(
          of: find.byType(AnimatedScale),
          matching: find.byType(ScaleTransition),
        ),
      );
      expect(scale.scale.value, inExclusiveRange(0, 1));
      expect(find.byKey(const Key('fab')).hitTestable(), findsNothing);
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(
        identical(tester.element(find.byKey(const Key('fab'))), element),
        isTrue,
      );
      await tester.tap(find.byKey(const Key('fab')));
      expect(taps, 1);
    },
  );

  testWidgets('tab fade-through retains tab state and scroll position', (
    tester,
  ) async {
    var index = 0;
    late StateSetter update;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return RetainedTabTransition(
              index: index,
              children: [
                ListView.builder(
                  key: const Key('recipes'),
                  controller: scroll,
                  itemCount: 60,
                  itemBuilder: (_, index) =>
                      ListTile(title: Text('Recipe $index')),
                ),
                const Center(child: Text('Shopping')),
              ],
            );
          },
        ),
      ),
    );
    scroll.jumpTo(450);
    await tester.pump();
    final element = tester.element(find.byKey(const Key('recipes')));
    update(() => index = 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final shoppingOpacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('Shopping'), matching: find.byType(Opacity)),
    );
    expect(shoppingOpacity.opacity, 0);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipes')), findsNothing);
    update(() => index = 0);
    await tester.pumpAndSettle();
    expect(scroll.offset, 450);
    expect(
      identical(tester.element(find.byKey(const Key('recipes'))), element),
      isTrue,
    );
  });

  testWidgets('reduced motion changes FAB and tab immediately', (tester) async {
    var index = 0;
    var visible = true;
    late StateSetter update;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Column(
              children: [
                ScrollAwareFab(visible: visible, child: const Text('Add')),
                Expanded(
                  child: RetainedTabTransition(
                    index: index,
                    children: const [
                      Center(child: Text('Recipes')),
                      Center(child: Text('Shopping')),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        reduced: true,
      ),
    );
    update(() {
      visible = false;
      index = 1;
    });
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
    expect(
      tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).duration,
      Duration.zero,
    );
    expect(find.text('Recipes'), findsNothing);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.text('Shopping'),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      1,
    );
  });

  for (final reduced in [false, true]) {
    testWidgets('nested Material pages honor reduced motion=$reduced', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext routeContext;
      await tester.pumpWidget(
        _host(
          Navigator(
            key: navigator,
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              settings: settings,
              builder: (context) {
                routeContext = context;
                return const Text('List');
              },
            ),
          ),
          reduced: reduced,
        ),
      );
      final route = cookdexRoute<void>(
        routeContext,
        builder: (_) => const Scaffold(body: Text('Detail')),
      );
      navigator.currentState!.push(route);
      await tester.pump();
      expect(route.transitionDuration == Duration.zero, reduced);
      await tester.pumpAndSettle();
      expect(find.text('Detail'), findsOneWidget);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('List'), findsOneWidget);
    });
  }

  testWidgets('predictive gesture can cancel and commit a Material page', (
    tester,
  ) async {
    late BuildContext routeContext;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            routeContext = context;
            return const Text('List');
          },
        ),
      ),
    );
    Navigator.of(routeContext).push(
      cookdexRoute<void>(
        routeContext,
        builder: (_) => const Scaffold(body: Text('Detail')),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> gesture(
      String method, [
      Map<String, dynamic>? arguments,
    ]) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
      await tester.pump();
    }

    final start = <String, dynamic>{
      'touchOffset': <double>[5, 300],
      'progress': 0.0,
      'swipeEdge': 0,
    };
    await gesture('startBackGesture', start);
    await gesture('updateBackGestureProgress', <String, dynamic>{
      'touchOffset': <double>[100, 300],
      'progress': .4,
      'swipeEdge': 0,
    });
    expect(tester.getTopLeft(find.text('Detail')).dx, greaterThan(0));
    await gesture('cancelBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('Detail'), findsOneWidget);
    await gesture('startBackGesture', start);
    await gesture('commitBackGesture');
    await tester.pumpAndSettle();
    expect(find.text('List'), findsOneWidget);
  });
}
