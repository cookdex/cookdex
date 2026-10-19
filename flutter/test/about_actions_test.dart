import 'package:cookdex/export_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ShellPlatform, ImportFakeService;
import 'recipe_store_test.dart' show FakeRepository, recipe;

class _AppPlatform extends ShellPlatform {
  _AppPlatform(this.android);
  final bool android;
  final opened = <String>[];
  @override
  bool get isAndroid => android;
  @override
  Future<void> openSource(String url) async => opened.add(url);
}

class _Exports extends NativeExportPlatform {
  String? copied, shared;
  bool fail = false;
  @override
  Future<ExportOutcome> copy(String text) async {
    if (fail) throw StateError('synthetic failure');
    copied = text;
    return ExportOutcome.copied;
  }

  @override
  Future<ExportOutcome> shareText(String text, {required String title}) async {
    if (fail) throw StateError('synthetic failure');
    shared = text;
    return ExportOutcome.shareOpened;
  }
}

void main() {
  for (final android in [true, false]) {
    testWidgets(
      'About links dispatch and report ${android ? 'Android' : 'Windows'} outcomes',
      (tester) async {
        final prefs = LocalPreferences.memory();
        final store = RecipeStore(FakeRepository([recipe('one')]), prefs);
        await store.initialize();
        final platform = _AppPlatform(android);
        final exports = _Exports();
        await tester.pumpWidget(
          CookdexApp(
            store: store,
            platform: platform,
            importService: ImportFakeService(),
            exportService: ExportService(platform: exports),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        final scrollable = find.descendant(
          of: find.byKey(const PageStorageKey('settings')),
          matching: find.byType(Scrollable),
        );
        Future<void> tap(String label) async {
          await tester.scrollUntilVisible(
            find.text(label),
            200,
            scrollable: scrollable,
          );
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await tap('cookdex on GitHub');
        expect(platform.opened, [cookdexGitHubUrl]);
        expect(find.text('Updates, source code and help'), findsOneWidget);
        await tap('Share cookdex');
        if (android) {
          expect(exports.shared, cookdexShareText);
          expect(exports.copied, isNull);
        } else {
          expect(exports.copied, cookdexDownloadUrl);
          expect(exports.shared, isNull);
          expect(find.text('Link copied'), findsOneWidget);
        }
        exports.fail = true;
        await tap('Share cookdex');
        expect(
          find.text('Could not share cookdex. Please try again.'),
          findsOneWidget,
        );
        expect(find.textContaining('synthetic failure'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
        prefs.dispose();
      },
    );
  }
}
