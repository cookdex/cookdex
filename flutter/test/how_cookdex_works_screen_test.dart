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
  test('help follows the reviewed section and subheading order', () {
    expect(helpSections.map((section) => section.title), [
      'Getting started',
      'Adding and editing recipes',
      'Smart Import',
      'Smart Create',
      'Your Gemini key',
      'Finding recipes',
      'Reading and cooking',
      'Shopping list',
      'Sharing recipes',
      'Syncing your devices',
      'Backups and moving phones',
      'Ingredients and tags',
      'Appearance and settings',
      'What’s kept and what’s sent',
      'Coming later',
      'Problems and feedback',
    ]);
    expect(helpSections.expand((s) => s.groups).map((group) => group.title), [
      'Websites',
      'YouTube',
      'Photos',
      'Text',
      'Social apps',
      'Smart Create settings',
      'On your device',
      'What Smart Import sends',
      'What Smart Create sends',
      'How Google uses what you send',
      'Other connections and copies',
      'Removing your data',
    ]);
  });

  test(
    'Smart Create help covers options, estimates and both food settings',
    () {
      final guide = helpSections.singleWhere(
        (section) => section.id == 'create',
      );
      final wording = [
        ...guide.paragraphs,
        ...guide.groups.single.paragraphs,
      ].join(' ');
      for (final phrase in [
        'What you have',
        'Options',
        'per serving',
        'aren’t saved with the recipe',
        'Foods to avoid',
        'Other preferences',
      ]) {
        expect(wording, contains(phrase));
      }
      final data = dataHelp.groups.singleWhere(
        (g) => g.title == 'What Smart Create sends',
      );
      expect(
        data.paragraphs.where((p) => p.contains('other preferences')),
        hasLength(2),
      );
    },
  );

  testWidgets('help starts with quick steps and expands only chosen sections', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(helpTitle), findsOneWidget);
    expect(find.text(helpSections.first.paragraphs.first), findsOneWidget);
    final adding = helpSections.firstWhere((section) => section.id == 'adding');
    expect(find.text(adding.paragraphs.first), findsNothing);
    await _expand(tester, 'adding');
    expect(find.text(adding.paragraphs.first), findsOneWidget);
    await _expand(tester, 'adding');
    expect(find.text(adding.paragraphs.first), findsNothing);
  });

  testWidgets('every help link opens its intended destination', (tester) async {
    final opened = <String>[];
    await _pump(tester, openUrl: (url) async => opened.add(url));
    const destinations = {
      'smart': {
        'Open Google AI Studio': 'https://aistudio.google.com/apikey',
        'Google’s key setup guide':
            'https://ai.google.dev/gemini-api/docs/api-key',
      },
      'data': {
        'Google’s Gemini API terms': 'https://ai.google.dev/gemini-api/terms',
      },
      'feedback': {
        'Report a problem on GitHub':
            'https://github.com/cookdex/cookdex/issues',
      },
    };
    for (final section in destinations.entries) {
      await _expand(tester, section.key);
      for (final link in section.value.entries) {
        final button = find.text(link.key);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        await tester.tap(button);
        expect(opened.last, link.value);
      }
    }
    expect(opened, hasLength(4));
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
        for (final paragraph in [
          ...section.paragraphs,
          for (final group in section.groups) ...group.paragraphs,
        ]) {
          await _reveal(
            tester,
            find.byKey(ValueKey('help-paragraph-$paragraph')),
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );
}
