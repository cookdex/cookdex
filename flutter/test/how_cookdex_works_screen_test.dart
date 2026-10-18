import 'package:cookdex/help_content.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  Future<String> Function()? loadAppInfo,
  Future<void> Function(String)? openUrl,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: cookdexTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: HowCookdexWorksScreen(
        loadAppInfo: loadAppInfo ?? () async => 'cookdex 0.9.0\nBuild: 9002',
        openUrl: openUrl ?? (_) async {},
      ),
    ),
  );
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _expand(WidgetTester tester, String id) async {
  final tile = find.byKey(PageStorageKey('help-$id'));
  await _reveal(tester, tile);
  await tester.tap(find.descendant(of: tile, matching: find.byType(ListTile)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('help starts with quick steps and expands only chosen sections', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(helpTitle), findsOneWidget);
    expect(find.text(helpSections.first.paragraphs.first), findsOneWidget);
    expect(find.text(helpSections[1].paragraphs.first), findsNothing);
    await _expand(tester, 'adding');
    expect(find.text(helpSections[1].paragraphs.first), findsOneWidget);
    await _expand(tester, 'adding');
    expect(find.text(helpSections[1].paragraphs.first), findsNothing);
  });

  testWidgets('Google setup links open the official source through platform', (
    tester,
  ) async {
    final opened = <String>[];
    await _pump(tester, openUrl: (url) async => opened.add(url));
    await _expand(tester, 'smart');
    final section = helpSections.firstWhere((section) => section.id == 'smart');
    for (final link in section.links) {
      await _reveal(tester, find.text(link.label));
      await tester.tap(find.text(link.label));
      await tester.pumpAndSettle();
    }
    expect(opened, section.links.map((link) => link.url).toList());
  });

  testWidgets('Copy app info copies the platform details without a send', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    const info = 'cookdex 0.9.0\nBuild: 9002\nDevice: Pixel 9 Pro\nAndroid: 16';
    await _pump(tester, loadAppInfo: () async => info);
    await _expand(tester, 'feedback');
    await _reveal(tester, find.text(helpCopyAppInfo));
    await tester.tap(find.text(helpCopyAppInfo));
    await tester.pumpAndSettle();
    final clipboard = calls.where((call) => call.method == 'Clipboard.setData');
    expect(clipboard.single.arguments, {'text': info});
    expect(find.text(helpAppInfoCopied), findsOneWidget);
  });

  testWidgets('app-info errors explain the failure and allow retry', (
    tester,
  ) async {
    await _pump(
      tester,
      loadAppInfo: () async => throw StateError('native error'),
    );
    await _expand(tester, 'feedback');
    await _reveal(tester, find.text(helpCopyAppInfo));
    await tester.tap(find.text(helpCopyAppInfo));
    await tester.pumpAndSettle();
    expect(find.text(helpAppInfoFailure), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
    expect(find.textContaining('native error'), findsNothing);
  });

  testWidgets(
    'large system text leaves every section readable without overflow',
    (tester) async {
      await _pump(tester, textScale: 2);
      for (final section in helpSections.skip(1)) {
        await _expand(tester, section.id);
        for (final paragraph in section.paragraphs) {
          await _reveal(tester, find.text(paragraph));
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
