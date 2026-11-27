import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/help_content.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/snapshots_screen.dart';
import 'package:cookdex/ui/text_import_review.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'import_test.dart'
    show ImportFakeService, ImportRepositoryFake, candidate;
import 'recipe_store_test.dart' show recipe;
import 'text_import_review_test.dart' show block;

class CenteredPageFixture {
  late final Widget page;
  final exported = <String>[];
  final restored = <String>[];
  final opened = <String>[];
  int loads = 0;
  int reviewed = 0;
  ImportController? importer;
  ImportFakeService? service;
  ImportRepositoryFake? repository;

  static Future<CenteredPageFixture> create(String name) async {
    final fixture = CenteredPageFixture();
    switch (name) {
      case 'help':
        fixture.page = HowCookdexWorksScreen(
          loadAppInfo: () async => 'cookdex 1.10.5+20005 · Synthetic fixture',
          openUrl: (url) async => fixture.opened.add(url),
        );
      case 'snapshots':
        fixture.page = SnapshotsScreen(
          load: () async {
            fixture.loads++;
            return SnapshotListing(
              entries: [
                for (var i = 0; i < 8; i++)
                  LocalSnapshotEntry(
                    id: 'snapshot-$i',
                    createdAt: DateTime(2026, 11, 21 - i, 9, 30),
                    recipeCount: 30 - i,
                    omittedCount: 0,
                    reason: i == 0 ? 'before_restore' : 'automatic',
                  ),
              ],
            );
          },
          onRestore: (entry) async => fixture.restored.add(entry.id),
          onExport: (entry) async => fixture.exported.add(entry.id),
        );
      case 'text-review':
        final preferences = LocalPreferences.memory();
        final repository = ImportRepositoryFake([]);
        final store = RecipeStore(repository, preferences);
        await store.initialize();
        addTearDown(() {
          store.dispose();
          preferences.dispose();
        });
        fixture.repository = repository;
        fixture.page = TextImportReview(
          blocks: [
            for (final (index, title) in [
              'Lemon lentil bowl',
              'Roasted tomato soup',
              'Garden vegetable rice',
              'Apple and cinnamon porridge',
              'Creamy white beans',
              'Herb potatoes',
              'Carrot and ginger soup',
              'Crisp cucumber salad',
              'Summer berry crumble',
              'Spinach and feta pie',
              'Chickpea stew',
              'Warm lentil salad',
            ].indexed)
              block(recipe('incoming-$index', title: title)),
          ],
          store: store,
          service: ImportFakeService(),
          onReview: (_, _) async => null,
        );
      case 'smart-import':
        final service = ImportFakeService()
          ..result = ImportDiscovery(
            candidates: [candidate('incoming', 'Garden vegetable soup')],
          );
        final controller = ImportController(
          service: service,
          storage: MemoryDraftStorage(),
        );
        fixture.service = service;
        fixture.importer = controller;
        addTearDown(controller.dispose);
        fixture.page = ImportScreen(
          controller: controller,
          initialInput: (controller) async {
            controller.text = 'Garden vegetable soup\n\nServes 4\n\n2 carrots\n1 onion\n2 cups vegetable stock\n1 cup white beans\n\nChop the vegetables.\nSimmer until tender.\nServe warm.';
            controller.changed();
          },
          onReview: (_, _) async {
            fixture.reviewed++;
            return null;
          },
        );
      default:
        throw ArgumentError.value(name);
    }
    return fixture;
  }
}

Finder centeredPageScroll() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

Future<void> _margins(WidgetTester tester) async {
  final scroll = centeredPageScroll();
  final position = tester.state<ScrollableState>(scroll).position;
  final rect = tester.getRect(scroll);
  expect(rect.width, 1280);
  expect(position.maxScrollExtent, greaterThan(0));
  for (final x in [rect.left + 24, rect.right - 24]) {
    final start = Offset(x, rect.center.dy);
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.dragFrom(start, const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: 'Touch from margin $x');
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: start,
        scrollDelta: const Offset(0, 140),
      ),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: 'Wheel from margin $x');
  }
  position.jumpTo(0);
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final name in ['help', 'snapshots', 'text-review', 'smart-import']) {
      testWidgets(
        '$name scrolls from both margins and retains controls on ${platform.name}',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = const Size(1280, 600);
          addTearDown(tester.view.reset);
          final fixture = await CenteredPageFixture.create(name);
          await tester.pumpWidget(
            MaterialApp(
              theme: cookdexTheme().copyWith(platform: platform),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.5)),
                child: child!,
              ),
              home: fixture.page,
            ),
          );
          await tester.pumpAndSettle();
          final content = name == 'smart-import'
              ? find.byType(TextField).first
              : find.byType(Card).first;
          expect(tester.getSize(content).width, switch (name) {
            'help' => 728,
            'smart-import' => 712,
            _ => 608,
          });
          await _margins(tester);
          switch (name) {
            case 'help':
              final section = helpSections.firstWhere(
                (section) => section.id == 'adding',
              );
              final tile = find.byKey(const PageStorageKey('help-adding'));
              await tester.ensureVisible(tile);
              await tester.pumpAndSettle();
              await tester.tap(
                find.descendant(of: tile, matching: find.byType(ListTile)),
              );
              await tester.pumpAndSettle();
              expect(find.text(section.paragraphs.first), findsOneWidget);
              expect(fixture.opened, isEmpty);
            case 'snapshots':
              await tester.ensureVisible(find.text('Export ZIP').first);
              await tester.pumpAndSettle();
              await tester.tap(find.text('Export ZIP').first);
              await tester.pumpAndSettle();
              expect(fixture.exported, ['snapshot-0']);
              expect(fixture.loads, 1);
              await tester.tap(find.text('Restore').first);
              await tester.pumpAndSettle();
              expect(fixture.restored, ['snapshot-0']);
              expect(fixture.loads, 2);
            case 'text-review':
              final first = find.byKey(const ValueKey('text-import-0'));
              expect(tester.widget<CheckboxListTile>(first).value, isTrue);
              await tester.tap(first);
              await tester.pumpAndSettle();
              expect(tester.widget<CheckboxListTile>(first).value, isFalse);
              await tester.scrollUntilVisible(
                find.text('Import selected (11)'),
                180,
                scrollable: centeredPageScroll(),
              );
              await tester.pumpAndSettle();
              expect(
                find.text('Import selected (11)').hitTestable(),
                findsOneWidget,
              );
              expect(fixture.repository!.imports, 0);
            case 'smart-import':
              final original = fixture.importer!.text;
              await tester.tap(find.widgetWithText(TextButton, 'Link'));
              await tester.pumpAndSettle();
              expect(fixture.importer!.tab, ImportTab.link);
              await tester.tap(find.widgetWithText(TextButton, 'Text'));
              await tester.pumpAndSettle();
              expect(fixture.importer!.text, original);
              await tester.tap(find.byKey(const Key('smart-import-action')));
              await tester.pumpAndSettle();
              expect(fixture.service!.received, original);
              expect(fixture.reviewed, 1);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
