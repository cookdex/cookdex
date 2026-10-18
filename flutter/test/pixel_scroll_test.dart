import 'package:cookdex/ui/pixel_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final ratio in [1.0, 2.0, 2.625, 3.5]) {
    testWidgets('fractional drags retain distance at DPR $ratio', (
      tester,
    ) async {
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(400 * ratio, 600 * ratio);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = PixelScrollController(initialScrollOffset: 200);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PixelSingleChildScrollView(
              controller: controller,
              child: const SizedBox(height: 4000.3),
            ),
          ),
        ),
      );
      final drag = controller.position.drag(DragStartDetails(), () {});
      for (var i = 0; i < 1000; i++) {
        drag.update(
          DragUpdateDetails(
            delta: const Offset(0, -.01),
            primaryDelta: -.01,
            globalPosition: Offset.zero,
          ),
        );
        expect(
          (controller.offset * ratio - (controller.offset * ratio).round())
              .abs(),
          lessThan(1e-7),
        );
      }
      expect(controller.offset, closeTo(210, .5 / ratio + 1e-7));
      for (var i = 0; i < 1000; i++) {
        drag.update(
          DragUpdateDetails(
            delta: const Offset(0, .01),
            primaryDelta: .01,
            globalPosition: Offset.zero,
          ),
        );
      }
      expect(controller.offset, closeTo(200, 1e-7));
      drag.cancel();
      controller.jumpTo(317.12345);
      expect(
        controller.offset * ratio,
        closeTo((317.12345 * ratio).round(), 1e-7),
      );
      final animation = controller.animateTo(
        500.123,
        duration: const Duration(milliseconds: 100),
        curve: Curves.linear,
      );
      await tester.pumpAndSettle();
      await animation;
      expect(
        controller.offset * ratio,
        closeTo((500.123 * ratio).round(), 1e-7),
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      // The content's fractional endpoint is floored, never rounded outward.
      // Truncation must stay strictly below one physical pixel at every DPR.
      final rawEndpoint = 4000.3 - controller.position.viewportDimension;
      final endpointTruncation =
          (rawEndpoint - controller.position.maxScrollExtent) * ratio;
      expect(endpointTruncation, greaterThanOrEqualTo(0));
      expect(endpointTruncation, lessThan(1));
      expect(controller.offset, controller.position.maxScrollExtent);
      expect(
        controller.offset * ratio,
        closeTo((controller.offset * ratio).round(), 1e-7),
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets(
    'variable row edits and reorder stay reachable at fractional DPR',
    (tester) async {
      const ratio = 2.625;
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = const Size(400 * ratio, 600 * ratio);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = PixelScrollController();
      final rows = List.generate(20, (index) => index);
      var compact = false;
      late StateSetter updateRows;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                updateRows = setState;
                return PixelListView(
                  controller: controller,
                  children: [
                    for (final id in rows)
                      SizedBox(
                        key: ValueKey('row-$id'),
                        height: compact
                            ? 42.3 + id % 3 * 7.1
                            : 110.7 + id % 4 * 23.3,
                        child: Center(child: Text('Row $id')),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final previousOffset = controller.offset;
      expect(previousOffset, greaterThan(600));
      // Shrinking variable-height content while at its old end forces viewport
      // correction; moving a keyed row across the viewport also checks identity.
      updateRows(() {
        compact = true;
        rows.add(rows.removeAt(3));
      });
      await tester.pumpAndSettle();
      expect(controller.offset, lessThan(previousOffset));
      expect(
        controller.offset,
        inInclusiveRange(
          controller.position.minScrollExtent,
          controller.position.maxScrollExtent,
        ),
      );
      void expectWholePhysicalPixel() {
        final physicalOffset = controller.offset * ratio;
        expect(physicalOffset, closeTo(physicalOffset.roundToDouble(), 1e-7));
        expect(tester.takeException(), isNull);
      }

      expectWholePhysicalPixel();
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expectWholePhysicalPixel();
      expect(find.text('Row 3').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('row-3')));
      await tester.pumpAndSettle();
      expectWholePhysicalPixel();
      expect(find.text('Row 3').hitTestable(), findsOneWidget);
      controller.jumpTo(controller.position.minScrollExtent);
      await tester.pumpAndSettle();
      expectWholePhysicalPixel();
      expect(find.text('Row 0').hitTestable(), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );

  testWidgets('implicit nested axes get distinct snapping controllers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        scrollBehavior: const CookdexScrollBehavior(),
        home: Scaffold(
          body: PixelListView(
            children: [
              SizedBox(
                height: 100,
                child: PixelSingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: 2000, child: Text('Wide')),
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      ),
    );
    final states = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .toList();
    expect(states, hasLength(2));
    expect(states.every((s) => s.position is PixelScrollPosition), isTrue);
    expect(identical(states[0].position, states[1].position), isFalse);
    await tester.drag(
      find.byType(PixelSingleChildScrollView),
      const Offset(-100, 0),
    );
    await tester.pumpAndSettle();
    expect(
      states
          .singleWhere((s) => s.position.axis == Axis.horizontal)
          .position
          .pixels,
      greaterThan(50),
    );
    expect(
      states
          .singleWhere((s) => s.position.axis == Axis.vertical)
          .position
          .pixels,
      0,
    );
  });
}
