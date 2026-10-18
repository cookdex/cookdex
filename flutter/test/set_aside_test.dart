import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/help_content.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/recipes_screen.dart';
import 'package:cookdex/ui/backup_feedback.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/polish_fixtures.dart';

class SetAsideFake extends PolishRepository implements SetAsideRepository {
  int count = 2;
  int discards = 0;
  @override
  CollectionSnapshot get current {
    final base = recipes.isEmpty
        ? CollectionSnapshot(
            setAsideCount: 0,
            generation: generation,
            summaries: const [],
            shopping: const [],
            shoppingCategories: const [],
            conflicts: const [],
            hasPrevious: false,
          )
        : super.current;
    return CollectionSnapshot(
      setAsideCount: count,
      generation: base.generation,
      summaries: base.summaries,
      shopping: base.shopping,
      shoppingCategories: base.shoppingCategories,
      conflicts: base.conflicts,
      hasPrevious: base.hasPrevious,
    );
  }

  @override
  Future<CollectionSnapshot> discardSetAside(int expected) async {
    if (expected != generation) throw StateError('Library changed');
    discards++;
    count = 0;
    generation++;
    return current;
  }
}

Future<void> fonts(WidgetTester tester) async {
  final sdk = Platform.environment['FLUTTER_SDK'];
  if (sdk == null) return;
  await tester.runAsync(() async {
    final font = FontLoader('Roboto');
    for (final weight in ['regular', 'bold']) {
      font.addFont(
        File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await font.load();
    for (final family in [
      'MaterialSymbolsRounded',
      'MaterialSymbolsOutlined',
    ]) {
      final font = FontLoader('packages/material_symbols_icons/$family');
      font.addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/$family.ttf',
        ),
      );
      await font.load();
    }
  });
}

void main() {
  for (final config in [
    ('small', const Size(320, 800), 1.0),
    ('normal', const Size(390, 844), 1.0),
    ('largest', const Size(390, 844), 2.0),
    ('tablet', const Size(1280, 800), 1.0),
  ]) {
    testWidgets('${config.$1} set-aside notice and confirmed discard', (
      tester,
    ) async {
      await fonts(tester);
      tester.view.physicalSize = config.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prefs = LocalPreferences.memory();
      prefs.setRecipeTextSize(RecipeTextSize.extraLarge);
      final repo = SetAsideFake();
      final store = RecipeStore(repo, prefs);
      await store.initialize();
      Widget app({bool dark = false, Widget? home}) => RepaintBoundary(
        key: const Key('capture'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: cookdexTheme(
            colors: dark ? cookdexColors : cookdexLightColors,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(config.$3)),
            child: child!,
          ),
          home:
              home ??
              Scaffold(
                body: RecipesScreen(
                  store: store,
                  preferences: prefs,
                  onOpenRecipe: (_) {},
                  onAdd: () {},
                  onActions: (_) {},
                  onRestore: () {},
                  onHelp: () {},
                ),
              ),
        ),
      );
      Future<void> shot(String name) async {
        expect(tester.takeException(), isNull);
        if (Platform.environment['SET_ASIDE_SCREENSHOTS'] != '1') return;
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/set-aside/screens/${config.$1}-$name.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('2 recipes set aside · Sync paused'), findsOneWidget);
      if (config.$1 == 'small' || config.$1 == 'normal') {
        for (final favorite in [false, true]) {
          for (final view in RecipeView.values) {
            prefs.setFavoritesOnly(favorite);
            prefs.setView(view);
            await tester.pumpAndSettle();
            await shot('${view.name}-favorites-$favorite');
          }
        }
        prefs.setFavoritesOnly(false);
        prefs.setView(RecipeView.cards);
        await tester.pumpAndSettle();
      } else {
        await shot('notice');
      }
      await tester.tap(find.text('Review options'));
      await tester.pumpAndSettle();
      await shot('options');
      await tester.tap(find.text('Discard…'));
      await tester.pumpAndSettle();
      expect(find.textContaining('cannot undo'), findsOneWidget);
      expect(repo.discards, 0);
      await shot('confirm');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.discards, 0);
      expect(store.setAsideCount, 2);
      if (config.$1 == 'normal') {
        await tester.pumpWidget(app(dark: true));
        await tester.pumpAndSettle();
        await shot('dark-notice');
      }
      await tester.tap(find.text('Review options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(repo.discards, 1);
      expect(store.setAsideCount, 0);
      expect(find.text('Review options'), findsNothing);
      expect(store.summaries.length, 12);
      final context = tester.element(find.byType(RecipesScreen));
      final feedback = showBackupSaved(context, 2);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('2 set-aside recipes were left out'),
        findsOneWidget,
      );
      await shot('backup-omissions');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await feedback;
      final cookbookFeedback = showCookbookSaved(context, 1);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('1 set-aside recipe was left out'),
        findsOneWidget,
      );
      expect(find.text('Cookbook saved'), findsOneWidget);
      await shot('cookbook-omissions');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await cookbookFeedback;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await tester.pumpAndSettle();
      repo.recipes.clear();
      repo.count = 2;
      repo.generation++;
      await store.refresh();
      await tester.pumpAndSettle();
      await shot('all-set-aside');
      await tester.tap(find.text('Review options'));
      await tester.pumpAndSettle();
      repo.generation++;
      await tester.tap(find.text('Discard…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(
        repo.discards,
        1,
        reason: 'Stale confirmation cannot delete a newer collection',
      );
      expect(store.setAsideCount, 2);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      prefs.dispose();
      await tester.pumpWidget(
        app(
          home: HowCookdexWorksScreen(
            loadAppInfo: () async => 'Synthetic fixture',
            openUrl: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start here'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Backups'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backups'));
      await tester.pumpAndSettle();
      final paragraphs = helpSections
          .singleWhere((s) => s.id == 'backups')
          .paragraphs;
      for (var i = 0; i < 2; i++) {
        final paragraph = find.text(paragraphs[i]);
        await Scrollable.ensureVisible(tester.element(paragraph), alignment: 0);
        await tester.pumpAndSettle();
        await shot('help-${i == 0 ? 'recovery' : 'omissions'}');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
