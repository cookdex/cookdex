import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/export_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/recipe_scale_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart' show ImportFakeService, ShellPlatform;
import 'recipe_scaling_test.dart' show ScalingFake;

class RecordingRecipeExportPlatform implements ExportPlatform {
  final calls = <(String, String)>[];
  @override
  Future<ExportOutcome> copy(String text) async {
    calls.add(('copy', text));
    return ExportOutcome.copied;
  }

  @override
  Future<ExportOutcome> shareText(String text, {required String title}) async {
    calls.add(('message', text));
    return ExportOutcome.shareOpened;
  }

  @override
  Future<ExportOutcome> shareFile(
    String text, {
    required String filename,
  }) async {
    calls.add(('file', text));
    return ExportOutcome.shareOpened;
  }

  @override
  Future<ExportOutcome> save(String text, {required String filename}) async {
    calls.add(('save', text));
    return ExportOutcome.saved;
  }
}

void main() {
  testWidgets('sharing from a scaled recipe uses its saved yield and amounts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = LocalPreferences.memory();
    final repository = ScalingFake();
    final store = RecipeStore(repository, preferences);
    await store.initialize();
    final platform = RecordingRecipeExportPlatform();
    await tester.pumpWidget(
      CookdexApp(
        store: store,
        platform: ShellPlatform(),
        drafts: MemoryDraftStorage(),
        importDrafts: MemoryDraftStorage(),
        importService: ImportFakeService(),
        exportService: ExportService(
          platform: platform,
          exporter: (_) async =>
              throw StateError('Messages must not use Text v1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text("Mom's Taco Meat").hitTestable().first);
    await tester.pumpAndSettle();
    final scaleToggle = find.byKey(const Key('recipe-scale-toggle'));
    await tester.ensureVisible(scaleToggle);
    await tester.pumpAndSettle();
    expect(scaleToggle.hitTestable(), findsOneWidget);
    await tester.tap(scaleToggle);
    await tester.pumpAndSettle();
    final twice = find.byKey(const Key('recipe-scale-4'));
    await Scrollable.ensureVisible(tester.element(twice), alignment: .5);
    await tester.pumpAndSettle();
    expect(twice.hitTestable(), findsOneWidget);
    await tester.tap(twice);
    await tester.pumpAndSettle();
    expect(
      tester.widget<RecipeScaleControl>(find.byType(RecipeScaleControl)).scale,
      4,
    );
    expect(find.text('2/3 cup cream [fresh]'), findsOneWidget);

    for (final action in ['Copy text', 'Send as message']) {
      await tester.tap(find.byTooltip('Recipe actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share').hitTestable());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(action));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      final text = platform.calls.last.$2;
      expect(text, contains('Serves 4'));
      expect(text, contains('- ⅓ cup cream [fresh]'));
      expect(text, isNot(contains('2/3 cup')));
      expect(text, isNot(contains('Recipe Book')));
    }
    expect(platform.calls.map((call) => call.$1), ['copy', 'message']);
    expect(platform.calls.first.$2, platform.calls.last.$2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    preferences.dispose();
  });
}
