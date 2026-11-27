import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/ui/prepared_card_title.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _CountingPainter extends TextPainter {
  _CountingPainter({required super.text, required super.textDirection})
    : super(maxLines: 2, ellipsis: '\u2026');

  int layouts = 0;
  int disposals = 0;

  @override
  void layout({double minWidth = 0, double maxWidth = double.infinity}) {
    layouts++;
    super.layout(minWidth: minWidth, maxWidth: maxWidth);
  }

  @override
  void dispose() {
    disposals++;
    super.dispose();
  }
}

void main() {
  testWidgets('prepared titles match real-font pixels, bounds and baselines', (
    tester,
  ) async {
    final sdk = Platform.environment['FLUTTER_SDK']!;
    await tester.runAsync(() async {
      final font = FontLoader('Roboto');
      for (final weight in ['regular', 'medium', 'bold']) {
        font.addFont(
          File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
              .readAsBytes()
              .then(ByteData.sublistView),
        );
      }
      await font.load();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    const recipeTitle =
        'Roasted vegetables with chickpeas, lemon and fresh herbs';
    const boundaryKey = Key('capture');
    for (final (maxLines, isTags) in [(2, false), (1, false), (1, true)]) {
      final title = isTags
          ? 'Family dinner · Quick · Vegetarian · Meal prep · Budget friendly'
          : recipeTitle;
      for (final dark in [false, true]) {
        for (final width in [240.0, 310.0, 620.0]) {
          for (final scale in [1.0, 1.5, 1.8]) {
            for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
              final theme = cookdexTheme(
                colors: dark ? cookdexColors : cookdexLightColors,
              );
              final style = theme.textTheme.bodyMedium!
                  .merge(
                    isTags
                        ? theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : theme.textTheme.titleMedium?.copyWith(
                            fontWeight: maxLines == 1 ? FontWeight.w700 : null,
                          ),
                  )
                  .copyWith(inherit: false);
              final scaler = TextScaler.linear(scale);
              const behavior = TextHeightBehavior(
                applyHeightToFirstAscent: false,
              );
              final painter = TextPainter(
                text: TextSpan(text: title, style: style),
                textDirection: direction,
                textScaler: scaler,
                locale: const Locale('en', 'US'),
                maxLines: maxLines,
                ellipsis: '\u2026',
                textHeightBehavior: behavior,
              )..layout(maxWidth: width);
              final prepared = PreparedTitle(painter, maxWidth: width);
              Widget host(Widget child) => MaterialApp(
                theme: theme,
                home: Directionality(
                  textDirection: direction,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: RepaintBoundary(
                      key: boundaryKey,
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: SizedBox(
                          width: width,
                          height: 180,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Baseline(
                                baseline: 40,
                                baselineType: TextBaseline.alphabetic,
                                child: child,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              Future<Uint8List> pixels() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(boundaryKey),
                );
                return (await tester.runAsync(() async {
                  final image = await boundary.toImage();
                  final data = await image.toByteData(
                    format: ui.ImageByteFormat.rawRgba,
                  );
                  image.dispose();
                  return data!.buffer.asUint8List();
                }))!;
              }

              await tester.pumpWidget(
                host(
                  Text(
                    title,
                    style: style,
                    textScaler: scaler,
                    locale: const Locale('en', 'US'),
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: behavior,
                  ),
                ),
              );
              final expected = await pixels();
              final bounds = tester.getRect(find.text(title));
              await tester.pumpWidget(
                host(PreparedCardTitle(title, prepared: prepared)),
              );
              expect(find.text(title), findsOneWidget);
              expect(tester.getRect(find.text(title)), bounds);
              expect(
                await pixels(),
                expected,
                reason:
                    'dark=$dark width=$width scale=$scale dir=$direction lines=$maxLines tags=$isTags',
              );
              prepared.releaseCache();
              await tester.pumpWidget(const SizedBox());
            }
          }
        }
      }
    }
  });

  testWidgets('mounted leases survive eviction and reuse without layout', (
    tester,
  ) async {
    final painter = _CountingPainter(
      text: const TextSpan(text: 'Title', style: TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 200);
    final prepared = PreparedTitle(painter, maxWidth: 200);
    Widget host(double width, int count) => Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < count; i++)
                PreparedCardTitle('Title', prepared: prepared),
            ],
          ),
        ),
      ),
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(200, 2));
    expect(find.bySemanticsLabel('Title'), findsNWidgets(2));
    expect(painter.layouts, 1);
    prepared.releaseCache();
    expect(painter.disposals, 0);
    await tester.pumpWidget(host(120, 1));
    expect(painter.layouts, 1);
    expect(painter.disposals, 0);
    await tester.pumpWidget(host(200, 1));
    expect(painter.layouts, 1);
    await tester.pumpWidget(const SizedBox());
    expect(painter.disposals, 1);
    prepared.releaseCache();
    expect(painter.disposals, 1);
    semantics.dispose();
  });

  testWidgets(
    'refresh releases an evicted paragraph only after its last lease',
    (tester) async {
      _CountingPainter painter() => _CountingPainter(
        text: const TextSpan(text: 'Title', style: TextStyle(fontSize: 20)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 200);
      final originalPainter = painter();
      final refreshedPainter = painter();
      final original = PreparedTitle(originalPainter, maxWidth: 200);
      final refreshed = PreparedTitle(refreshedPainter, maxWidth: 200);
      Widget host(List<PreparedTitle> titles) => Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < titles.length; index++)
                  PreparedCardTitle(
                    'Title',
                    key: ValueKey(index),
                    prepared: titles[index],
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(host([original, original]));
      final originalBounds = tester.getRect(find.byKey(const ValueKey(0)));
      original.releaseCache();
      await tester.pumpWidget(host([refreshed, original]));
      expect(originalPainter.disposals, 0);
      expect(refreshedPainter.disposals, 0);
      expect(tester.getRect(find.byKey(const ValueKey(0))), originalBounds);
      refreshed.releaseCache();
      await tester.pumpWidget(host([refreshed]));
      expect(originalPainter.disposals, 1);
      expect(refreshedPainter.disposals, 0);
      expect(originalPainter.layouts, 1);
      expect(refreshedPainter.layouts, 1);
      await tester.pumpWidget(const SizedBox());
      expect(refreshedPainter.disposals, 1);
      original.releaseCache();
      refreshed.releaseCache();
      expect(originalPainter.disposals, 1);
      expect(refreshedPainter.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
