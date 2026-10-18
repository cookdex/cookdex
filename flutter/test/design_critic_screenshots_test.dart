// Synthetic, opt-in visual evidence. Never opens a device, private app data,
// a native core session, or a provider connection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/cook_controller.dart';
import 'package:cookdex/editor_controller.dart';
import 'package:cookdex/editor_model.dart';
import 'package:cookdex/help_content.dart';
import 'package:cookdex/import_controller.dart';
import 'package:cookdex/import_service.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/sync_controller.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/components.dart';
import 'package:cookdex/ui/how_cookdex_works_screen.dart';
import 'package:cookdex/ui/import_screen.dart';
import 'package:cookdex/ui/recipe_detail.dart';
import 'package:cookdex/ui/recipe_editor.dart';
import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/ui/shopping_screen.dart';
import 'package:cookdex/ui/smart_settings_screen.dart';
import 'package:cookdex/ui/sync_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/ui/window_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import 'import_test.dart'
    show ImportFakePlatform, ImportFakeService, ShellPlatform;
import 'recipe_store_test.dart' show summary;
import 'support/polish_fixtures.dart';
import 'sync_controller_test.dart' show FakeSyncBackend, syncStatus;

const _capture = Key('design-critic-capture');
const _longTitle =
    'Grandma’s slow-simmered Sunday vegetable and country-style pork supper with warm crusty bread';

// Overrides are repository-relative even when Flutter runs from flutter/.
// Leave the established design-pass destination unchanged when unset.
String get _outputDirectory {
  final configured = Platform.environment['DESIGN_CRITIC_OUTPUT'];
  if (configured == null || configured.isEmpty) {
    return '../artifacts/design-pass/screens';
  }
  return Directory(configured).isAbsolute
      ? configured
      : '${Directory.current.parent.path}/$configured';
}

class _Repository extends PolishRepository {
  _Repository({int count = 12, bool long = false, int shopping = 12}) {
    recipes.clear();
    for (var i = 0; i < count; i++) {
      recipes['$i'] = polishRecipe(
        '$i',
        long ? _longTitle : 'Family supper ${i + 1}',
      );
    }
    items = [
      for (var i = 0; i < shopping; i++)
        ShoppingItem(
          categoryId: 'other',
          id: 'item-$i',
          name: long
              ? 'boneless country-style pork ribs with a particularly long descriptive ingredient name'
              : [
                  'boneless country-style pork ribs',
                  'onion',
                  'carrots',
                  'tomato sauce',
                ][i % 4],
          measures: const [],
          contributorScales: const [],
          contributorIds: i == 1 ? const [] : recipes.keys.take(4).toList(),
          checked: i > 7,
          quantityText: i % 4 == 0 ? '1 lb' : '2',
        ),
    ];
  }
  List<ShoppingItem> items = [];
  List<Conflict> heads = [];
  bool previous = true;
  bool failRestore = false;
  bool failDetail = false;
  bool failPaste = false;
  @override
  Future<List<PastedIngredient>> parseIngredientPaste(
    String text,
    String section,
  ) async {
    if (failPaste) {
      throw const ServiceError(
        code: ErrorCode.validation,
        message: 'Could not review these ingredients. Your pasted text is still here. Try again.',
      );
    }
    return super.parseIngredientPaste(text, section);
  }

  @override
  CollectionSnapshot get current => CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: const [ShoppingCategory(id: 'other', name: 'Other')],
    generation: generation,
    summaries: recipes.values.map(summary).toList(),
    shopping: items,
    conflicts: heads,
    hasPrevious: previous,
  );
  @override
  Future<Recipe?> detail(String id) async {
    if (failDetail) throw StateError('Synthetic storage error');
    return super.detail(id);
  }

  @override
  Future<BackupPreview> previewRestore(Uint8List bytes) async {
    if (failRestore) {
      throw const ServiceError(
        code: ErrorCode.validation,
        message:
            'The recipe backup is incomplete or damaged. Choose another ZIP.',
      );
    }
    return const BackupPreview(
      RestoreReport(
        shoppingSetup: false,
        added: 12,
        updated: 3,
        skipped: 1,
        conflicts: ['existing conflict'],
      ),
      'synthetic',
    );
  }
}

class _Platform extends ShellPlatform {
  _Platform(this.android);
  final bool android;
  @override
  bool get isAndroid => android;
  @override
  Future<Uint8List?> pickRecipeZip() async => Uint8List.fromList([1, 2, 3]);
}

class _ImportPlatform extends ImportFakePlatform {
  bool hasKey = true;
  bool fail = false;
  Completer<SmartImportSettings>? pending;
  @override
  Future<SmartImportSettings> settings() async {
    if (fail) throw StateError('Synthetic settings error');
    return pending?.future ??
        SmartImportSettings(hasKey: hasKey, model: 'gemini-3.5-flash-lite');
  }
}

class _ImportService extends ImportFakeService
    implements ImportServiceToolsProvider {
  final _platform = _ImportPlatform();
  @override
  _ImportPlatform get platform => _platform;
  @override
  Future<String> jsonPrompt({
    bool photos = false,
    ProviderMode mode = ProviderMode.recipe,
  }) async =>
      'Read the recipe. Preserve exact quantities and complete directions. Use canonical units and keep preparation notes separate.';
  @override
  Future<String?> lastAiDiagnostics() async =>
      'Mode: Text\nModel: gemini-3.5-flash-lite\nValidation: accepted\nWarnings: Estimated servings and total time.\nNo personal inputs retained in this synthetic record.';
  @override
  Future<void> clearAiDiagnostics() async {}
}

class _Matrix {
  _Matrix(this.tester, this.profile, this.scale);
  final WidgetTester tester;
  final String profile;
  final double scale;
  final List<Map<String, Object?>> shots = [];
  final List<String> errors = [];
  bool complete = false;
  final List<String>? focus = Platform.environment['DESIGN_CRITIC_FOCUS']
      ?.split(',');
  int _mount = 0;
  Future<void> pump() async {
    // Bounded pumping also captures indeterminate progress without settling it.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 150));
      Object? exception;
      while ((exception = tester.takeException()) != null) {
        errors.add(exception.toString());
      }
    }
  }

  Future<void> mount(Widget child, {bool app = false}) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final pushed =
        child is SyncScreen ||
        child is SyncDeviceDetailsScreen ||
        child is PairingScreen ||
        child is ConflictsScreen ||
        child is HowCookdexWorksScreen ||
        child is SmartSettingsScreen ||
        child is RecipeEditor ||
        child is ImportScreen;
    await tester.pumpWidget(
      RepaintBoundary(
        key: _capture,
        child: app
            ? KeyedSubtree(key: ValueKey(_mount++), child: child)
            : MaterialApp(
                key: ValueKey(_mount++),
                debugShowCheckedModeBanner: false,
                theme: cookdexTheme().copyWith(
                  platform: profile == 'desktop'
                      ? TargetPlatform.windows
                      : TargetPlatform.android,
                ),
                home: pushed ? const Scaffold() : child,
                initialRoute: pushed ? '/screen' : '/',
                routes: pushed ? {'/screen': (_) => child} : const {},
              ),
      ),
    );
    await pump();
  }

  Future<void> shot(String name, {String? note}) async {
    await pump();
    if (focus != null && !focus!.any(name.startsWith)) return;
    final file = File(
      '$_outputDirectory/$profile-${scale == 1 ? 'default' : 'largest'}-$name.png',
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await file.parent.create(recursive: true);
      // Readers may still be inspecting the previous PNG during a refresh.
      // Publish complete pixels atomically and tolerate a short Windows lock.
      final pending = File('${file.path}.pending');
      await pending.writeAsBytes(data!.buffer.asUint8List());
      for (var attempt = 0; ; attempt++) {
        try {
          await pending.rename(file.path);
          break;
        } on FileSystemException {
          if (attempt == 9) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      image.dispose();
    });
    shots.add({
      'file': file.path,
      'screen': name,
      'systemTextScale': scale,
      'recipeTextSize': 'Extra large (1.3)',
      'note': note,
      'renderExceptions': [...errors],
    });
    errors.clear();
  }

  Future<void> tap(Finder finder) async {
    await pump();
    bool exists() {
      try {
        return finder.evaluate().isNotEmpty;
      } on StateError {
        return false;
      }
    }

    if (!exists()) {
      final vertical = find
          .byType(Scrollable)
          .evaluate()
          .map((e) => (e as StatefulElement).state)
          .whereType<ScrollableState>()
          .where((s) => s.position.axis == Axis.vertical);
      for (final scroll in vertical) {
        scroll.position.jumpTo(0);
        await pump();
        while (!exists() &&
            scroll.mounted &&
            scroll.position.pixels < scroll.position.maxScrollExtent) {
          scroll.position.jumpTo(
            (scroll.position.pixels + scroll.position.viewportDimension * .65)
                .clamp(0, scroll.position.maxScrollExtent),
          );
          await pump();
        }
        if (exists()) break;
      }
    }
    await tester.ensureVisible(finder.last);
    await pump();
    await tester.tap(finder.last);
    await pump();
  }

  Future<void> back() async {
    final overlay = find.byType(AlertDialog).last;
    final sheet = find.byType(BottomSheet).last;
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      Navigator.of(tester.element(overlay)).pop();
    } else if (find.byType(BottomSheet).evaluate().isNotEmpty) {
      Navigator.of(tester.element(sheet)).pop();
    } else {
      await tester.binding.handlePopRoute();
    }
    await pump();
  }

  // Cover every vertical section, including both independently scrollable
  // detail columns. Horizontal controls are captured at their starting edge.
  Future<void> pages(String name, {String? note, bool reset = true}) async {
    final overlay = find.byType(AlertDialog).evaluate().isNotEmpty
        ? find.byType(AlertDialog).last
        : find.byType(BottomSheet).evaluate().isNotEmpty
        ? find.byType(BottomSheet).last
        : null;
    final scrollables = overlay == null
        ? find.byType(Scrollable)
        : find.descendant(of: overlay, matching: find.byType(Scrollable));
    final states = scrollables
        .evaluate()
        .map((e) => (e as StatefulElement).state)
        .whereType<ScrollableState>()
        .where(
          (s) =>
              s.position.axis == Axis.vertical &&
              s.position.maxScrollExtent > 1,
        )
        .toList();
    if (reset) {
      for (final state in states) {
        state.position.jumpTo(0);
      }
    }
    await shot('$name-top', note: note);
    for (var column = 0; column < states.length; column++) {
      final s = states[column];
      var page = 0;
      while (s.mounted && s.position.pixels < s.position.maxScrollExtent - 1) {
        final position = s.position;
        position.jumpTo(
          (position.pixels + position.viewportDimension * .78).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
        await shot('$name-scroll${column + 1}-${++page}', note: note);
        if (page > 35) {
          throw StateError('Unexpectedly large synthetic screen $name');
        }
      }
      if (s.mounted) s.position.jumpTo(0);
      await pump();
    }
  }

  Future<void> manifest() async {
    await tester.runAsync(() async {
      final file = File(
        '$_outputDirectory/manifest-$profile-${scale == 1 ? 'default' : 'largest'}.json',
      );
      var entries = shots;
      if (focus != null && await file.exists()) {
        final existing =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        entries = [
          for (final s in existing['screenshots'] as List)
            if (!focus!.any(
              (prefix) => (s['screen'] as String).startsWith(prefix),
            ))
              Map<String, Object?>.from(s as Map),
          ...shots,
        ];
      }
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'profile': profile,
          'complete': complete,
          'focusPrefixes': focus,
          'coverage': focus == null ? 'Entire fixture' : 'Focused screens only',
          'systemTextScale': scale,
          'evidence': 'Actual Flutter widgets rendered by widget-test engine with real Roboto and Material Symbols fonts; synthetic data only.',
          'limitations': [
            '2.0 linear system scaling is a largest-Android-font stress proxy, not an Android nonlinear-font emulator measurement.',
            'Focused Android editor suggestion screenshots simulate a 260dp IME inset; no operating-system keyboard pixels or physical keyboard behavior are rendered.',
            'Live native camera preview, platform file pickers/share chooser and physical devices are not launched; scanner unavailable state uses a denied-permission method-channel fake.',
            'Cleanup and previous-save confirmations use the production confirmCookdex component with exact production text; native CoreSession callback flow is not invoked.',
          ],
          'screenshots': entries,
        }),
      );
    });
  }
}

Future<void> _editorSuggestionStates(_Matrix m, LocalPreferences prefs) async {
  const longIngredient =
      'boneless country-style pork ribs with a particularly long descriptive ingredient name';
  const longTag =
      'slow simmered family favorites for a leisurely weekend supper';
  final repository = _Repository(count: 1, shopping: 0);
  repository.recipes['0']!.fields.ingredients.add(
    const Ingredient(
      amount: Amount.unspecified(),
      unit: '',
      name: longIngredient,
      prepNote: '',
      optional: false,
      section: '',
    ),
  );
  repository.recipes['0']!.fields.tags.add(longTag);
  final store = RecipeStore(repository, prefs);
  await store.initialize();
  final c = await EditorController.create(
    store: store,
    storage: MemoryDraftStorage(),
  );
  c.draft.title = 'Synthetic suggestion editing';
  c.draft.sections.first.rows.addAll([
    EditableIngredient(amount: '2', name: 'onion'),
    EditableIngredient(amount: '3', name: 'carrots'),
  ]);
  c.draft.steps.add(
    EditableStep('Simmer gently until the vegetables are tender.'),
  );
  final row = c.draft.sections.first.rows.first;
  final tester = m.tester;
  final android = m.profile != 'desktop';
  final note = android
      ? 'Synthetic 260dp IME view inset; operating-system keyboard pixels are not rendered. Actual editor focus and suggestions are exercised.'
      : 'Desktop hardware-keyboard layout: actual editor focus and suggestions with no IME inset.';
  final strip = find.byKey(const ValueKey('editor-suggestion-strip'));
  await m.mount(RecipeEditor(controller: c));
  try {
    if (android) {
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await m.pump();
    }
    for (final (kind, key, query, option) in [
      ('unit', '${row.id}-unit', 'tb', 'tbsp'),
      ('ingredient', '${row.id}-name', 'particularly', longIngredient),
      ('tag', 'tag-input', 'slow', longTag),
    ]) {
      final field = find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(TextField),
      );
      await m.tap(field);
      await tester.enterText(field, '');
      await m.pump();
      expect(strip, findsOneWidget);
      expect(find.byType(ActionChip), findsWidgets);
      await m.shot('editor-suggestions-$kind-focused', note: note);
      await tester.drag(
        find.byWidgetPredicate((w) => w is CustomScrollView).first,
        const Offset(0, -60),
      );
      await m.pump();
      expect(strip, findsOneWidget);
      await m.shot('editor-suggestions-$kind-scrolling', note: note);
      await tester.ensureVisible(field);
      await tester.enterText(field, query);
      await m.pump();
      final chip = find.widgetWithText(ActionChip, option);
      expect(chip, findsOneWidget);
      await m.shot('editor-suggestions-$kind-filtered', note: note);
      if (kind != 'unit') {
        await tester.drag(
          find.descendant(
            of: strip,
            matching: find.byWidgetPredicate((w) => w is SingleChildScrollView),
          ),
          const Offset(-250, 0),
        );
        await m.pump();
        expect(strip, findsOneWidget);
        await m.shot('editor-suggestions-$kind-long-chip-scrolled', note: note);
      }
      // A long chip can be wider than the window. Select its visible portion
      // rather than an offscreen geometric center.
      await tester.ensureVisible(chip);
      await m.pump();
      final visibleChip = tester.getRect(chip).intersect(tester.getRect(strip));
      expect(visibleChip.width, greaterThan(0));
      await tester.tapAt(visibleChip.center);
      await m.pump();
      expect(strip, findsOneWidget);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      switch (kind) {
        case 'unit':
          expect(row.unit, option);
        case 'ingredient':
          expect(row.name, option);
        case 'tag':
          expect(c.draft.tags, contains(option));
      }
      await m.shot('editor-suggestions-$kind-selected', note: note);
      const unmatched = 'no matching suggestion for this synthetic text';
      await tester.enterText(field, unmatched);
      await m.pump();
      expect(strip, findsOneWidget);
      expect(find.byType(ActionChip), findsNothing);
      switch (kind) {
        case 'unit':
          expect(row.unit, unmatched);
        case 'ingredient':
          expect(row.name, unmatched);
        case 'tag':
          expect(c.draft.tagInput, unmatched);
      }
      await m.shot('editor-suggestions-$kind-no-match', note: note);
    }
  } finally {
    FocusManager.instance.primaryFocus?.unfocus();
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    store.dispose();
  }
}

Future<void> _fonts(WidgetTester tester) async {
  final sdk = Platform.environment['FLUTTER_SDK']!;
  await tester.runAsync(() async {
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'bold']) {
      roboto.addFont(
        File('$sdk/bin/cache/artifacts/material_fonts/roboto-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await roboto.load();
    final material = FontLoader('MaterialIcons');
    material.addFont(
      File('$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView),
    );
    await material.load();
    for (final family in [
      'MaterialSymbolsRounded',
      'MaterialSymbolsOutlined',
    ]) {
      final symbols = FontLoader('packages/material_symbols_icons/$family');
      symbols.addFont(
        rootBundle.load(
          'packages/material_symbols_icons/lib/fonts/$family.ttf',
        ),
      );
      await symbols.load();
    }
  });
}

void main() {
  final enabled = Platform.environment['DESIGN_CRITIC_SCREENSHOTS'] == '1';
  for (final profile in {
    'phone': const Size(390, 844),
    'tablet': const Size(1280, 800),
    'desktop': const Size(1280, 900),
  }.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('design critic ${profile.key} system scale $scale', (
        tester,
      ) async {
        if (!enabled) return;
        tester.view.physicalSize = profile.value;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        await _fonts(tester);
        final m = _Matrix(tester, profile.key, scale);
        final android = profile.key != 'desktop';
        final prefs = LocalPreferences.memory()
          ..recipeTextSize = RecipeTextSize.extraLarge;
        final repository = _Repository();
        final store = RecipeStore(repository, prefs);
        await store.initialize();
        final service = _ImportService();
        Future<void> app(RecipeStore s, {DraftStorage? drafts}) => m.mount(
          CookdexApp(
            store: s,
            platform: _Platform(android),
            drafts: drafts ?? MemoryDraftStorage(),
            importDrafts: MemoryDraftStorage(),
            importService: service,
          ),
          app: true,
        );
        try {
          for (final state in ['empty', 'one', 'many', 'long']) {
            final r = _Repository(
              count: state == 'empty'
                  ? 0
                  : state == 'one'
                  ? 1
                  : 12,
              long: state == 'long',
              shopping: 0,
            );
            final s = RecipeStore(r, prefs);
            await s.initialize();
            await app(s);
            await m.pages('recipes-$state');
            if (state == 'long') {
              await m.tap(find.text(_longTitle).first);
              expect(find.byType(RecipeDetail), findsOneWidget);
              await m.pages('recipe-long-name-extra-large');
            }
            if (state == 'empty') {
              // Fresh-device restore is a real production route.
              final restore = find.text('Restore a backup');
              if (restore.evaluate().isNotEmpty) {
                await m.tap(restore);
                await m.shot('restore-empty-preview');
                await m.back();
              }
            }
            await tester.pumpWidget(const SizedBox.shrink());
            s.dispose();
            prefs.scrollOffset = 0;
          }
          for (final state in ['loading', 'error']) {
            final r = _Repository(count: 0, shopping: 0);
            final s = RecipeStore(r, prefs);
            if (state == 'error') {
              await s.initialize();
              s.error = 'Could not read recipes. Try again.';
            }
            await app(s);
            await m.shot('recipes-$state');
            await tester.pumpWidget(const SizedBox.shrink());
            s.dispose();
          }
          for (final state in ['loading', 'error', 'missing']) {
            final r = _Repository(count: state == 'missing' ? 0 : 1);
            final s = RecipeStore(r, prefs);
            await s.initialize();
            final gate = Completer<Recipe?>();
            if (state == 'loading') r.detailGate = gate;
            if (state == 'error') r.failDetail = true;
            final cook = CookController(
              preferences: prefs,
              setWake: (_) async {},
            );
            await m.mount(
              Builder(
                builder: (context) => Scaffold(
                  body: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: RecipeTextScaler(
                        MediaQuery.textScalerOf(context),
                        1.3,
                      ),
                    ),
                    child: RecipeDetail(
                      store: s,
                      recipeId: '0',
                      cook: cook,
                      onBack: () {},
                      onActions: () {},
                      onEdit: () {},
                      onSource: (_) async {},
                      onAddToShopping: () {},
                    ),
                  ),
                ),
              ),
            );
            await m.shot('recipe-detail-$state');
            await tester.pumpWidget(const SizedBox.shrink());
            if (state == 'loading') gate.complete(null);
            cook.dispose();
            s.dispose();
          }
          await app(store);
          prefs.setView(RecipeView.compact);
          await m.pages('recipes-compact');
          prefs.setQuery('no matching synthetic recipe');
          await m.shot('recipes-no-match');
          prefs.resetSearch();
          prefs.setView(RecipeView.cards);
          await m.pump();
          await m.tap(find.byTooltip('Search fields'));
          expect(find.text('Search in'), findsOneWidget);
          await m.pages('search-fields-sheet');
          await m.back();
          await m.tap(find.byTooltip('Add recipe'));
          expect(find.text('Write a recipe'), findsOneWidget);
          expect(find.text('Search in'), findsNothing);
          await m.pages('add-recipe-sheet');
          await m.back();
          await m.tap(find.text('Family supper 1').first);
          expect(find.byType(RecipeDetail), findsOneWidget);
          await m.pages('recipe-detail-extra-large');
          await m.tap(find.text('Cook'));
          expect(find.text('Cooking'), findsOneWidget);
          await m.pages('cook-extra-large');
          await m.tap(find.byTooltip('Recipe actions'));
          await m.pages('recipe-actions-sheet');
          await m.tap(find.text('Share'));
          expect(find.text('Send as message'), findsOneWidget);
          await m.pages('share-options-sheet');
          await m.back();
          await m.tap(find.byTooltip('Recipe actions'));
          await m.tap(find.text('Delete'));
          expect(find.byType(AlertDialog), findsOneWidget);
          await m.shot('delete-recipe-confirmation');
          await m.back();
          await m.tap(find.text('Add to shopping list').first);
          await m.pages('shopping-selection');
          await m.back();
          await m.tap(find.text('Shopping list').last);
          await m.pages('shopping-shell');
          await m.tap(find.byTooltip('Shopping list options'));
          await m.shot('shopping-menu');
          await m.tap(find.text('Clear entire list'));
          expect(find.byType(AlertDialog), findsOneWidget);
          await m.shot('shopping-clear-confirmation');
          await m.back();
          await m.tap(find.text('Settings').last);
          await m.pages('settings-shell');
          await m.tap(find.text('Recipe text size'));
          await m.shot('appearance-text-size-sheet');
          await m.back();
          await m.tap(find.text('Restore recipe ZIP'));
          await m.shot('restore-preview');
          await m.tap(find.widgetWithText(TextButton, 'Restore'));
          expect(find.text('Recipes restored'), findsOneWidget);
          await m.shot('restore-success');
          await m.back();
          repository.failRestore = true;
          await m.tap(find.text('Restore recipe ZIP'));
          await m.shot('restore-error');
          await m.back();
          repository.failRestore = false;
          final unfinished = MemoryDraftStorage();
          await unfinished.write(
            EditorDraft(title: 'An unfinished family recipe').toJson(),
          );
          await app(store, drafts: unfinished);
          await m.tap(find.byTooltip('Add recipe'));
          await m.tap(find.text('Write a recipe'));
          expect(find.text('Resume draft?'), findsOneWidget);
          await m.shot('editor-resume-draft-dialog');
          await m.back();
          for (final state in ['unavailable', 'busy']) {
            await m.mount(
              SettingsScreen(
                hasPrevious: state != 'unavailable',
                busy: state == 'busy',
                syncSummary: '1 device · just now',
                onSync: () {},
                onDownloadRecipeZip: () {},
                onSaveReadableCookbook: () {},
                onRestoreRecipeZip: () {},
                onRecoverPreviousSave: () {},
                onCleanUpRecipes: () {},
                onSmartImportSettings: () {},
                onHowCookdexWorks: () {},
                shoppingKeepAwake: false,
                onShoppingKeepAwake: (_) {},
                recipeTextScale: 1.3,
                onRecipeTextScale: (_) {},
                isAndroid: android,
                wallpaperColors: false,
                onWallpaperColors: (_) {},
                version: '0.9.0+9003',
              ),
            );
            await m.pages('settings-$state');
          }

          for (final state in ['empty', 'one', 'many', 'long']) {
            final r = _Repository(
              count: 4,
              shopping: state == 'empty'
                  ? 0
                  : state == 'one'
                  ? 1
                  : 12,
              long: state == 'long',
            );
            final s = RecipeStore(r, prefs);
            await s.initialize();
            await m.mount(ShoppingScreen(store: s, onSaveText: (_) async {}));
            await m.pages('shopping-$state');
            if (state == 'many') {
              await m.tap(find.text('Checked (4)'));
              await m.pages('shopping-checked');
              final row = find
                  .textContaining('onion', findRichText: true)
                  .first;
              await tester.ensureVisible(row);
              await tester.longPress(row);
              await m.pages('shopping-edit-dialog');
              await m.back();
            }
            await tester.pumpWidget(const SizedBox.shrink());
            s.dispose();
          }

          for (final state in [
            'empty',
            'one',
            'populated',
            'long',
            'named-section',
            'multiple-sections',
            'review',
            'error',
            'saving',
          ]) {
            final c = await EditorController.create(
              store: store,
              storage: MemoryDraftStorage(),
              base: state == 'empty' || state == 'review'
                  ? null
                  : repository.recipes['0'],
              imported: state == 'review'
                  ? Candidate(
                      recipe: polishRecipe('review', _longTitle),
                      warnings: const [
                        'Estimated servings and total time. Review the generated directions.',
                      ],
                      ingredientSources: const [],
                      aiReview: AiReview(
                        guessedFields: ['servings', 'totalTime', 'tags'],
                        guessedSteps: Uint32List.fromList([0, 1, 2, 3]),
                      ),
                    )
                  : null,
            );
            if (state == 'one') {
              final rows = c.draft.sections.first.rows;
              rows.removeRange(1, rows.length);
              c.draft.steps.removeRange(1, c.draft.steps.length);
            }
            if (state == 'long') {
              c.draft.title = _longTitle;
              c.draft.totalTime =
                  '45 minutes, plus overnight resting and time to serve';
              c.draft.prepTime =
                  '30 minutes, plus at least two hours of proofing';
              c.draft.cookTime =
                  '1 hour and 30 minutes, until the vegetables are tender';
              c.draft.source = 'https://example.com/family-recipes/grandmas-slow-simmered-country-style-pork-and-vegetable-supper';
              c.draft.sections.first.rows.first.name = 'boneless country-style pork ribs with a particularly long descriptive ingredient name';
              c.draft.sections.first.rows.first.prepNote = 'trimmed of excess fat and cut into evenly sized serving portions';
              c.draft.sections.first.rows.first.showNote = true;
            }
            if (state == 'named-section' || state == 'multiple-sections') {
              c.draft.sections.first.name = 'Slow-simmered pork and vegetables';
            }
            if (state == 'multiple-sections') {
              c.draft.sections.add(
                EditableSection(
                  name: 'Fresh herb and lemon dressing for the finished supper',
                  rows: [
                    EditableIngredient(
                      amount: '2',
                      unit: 'tbsp',
                      name: 'olive oil',
                    ),
                    EditableIngredient(
                      amount: '1',
                      name: 'lemon',
                      prepNote: 'zested and juiced',
                      showNote: true,
                    ),
                  ],
                ),
              );
            }
            if (state == 'error') {
              c.draft.error = 'Could not save this recipe. Your changes are still here. Try again.';
              c.persistenceError = 'Could not save the local draft.';
            }
            if (state == 'saving') c.saving = true;
            await m.mount(RecipeEditor(controller: c));
            await m.pages('editor-$state');
            if (state == 'multiple-sections') {
              await m.tap(find.byTooltip('Section 2 options'));
              await m.shot('editor-section-options');
              await m.tap(find.text('Rename'));
              await m.pages('editor-section-rename-dialog');
              await m.back();
              final section = c.draft.sections.first;
              c.draft.pasteKind = 'ingredients';
              c.draft.pasteSectionId = section.id;
              c.draft.pasteText = '1 cup sugar\n2 chopped carrots';
              c.changed();
              await m.tap(find.byTooltip('Section 1 options'));
              await m.tap(find.text('Delete section'));
              expect(c.draft.sections.length, 2);
              expect(
                c.draft.error,
                'Apply or discard this section’s pasted text first.',
              );
              await m.pages('editor-section-unapplied-paste-error');
              await m.tap(
                find.descendant(
                  of: find.byKey(
                    ValueKey('${c.draft.sections.last.id}-actions'),
                  ),
                  matching: find.text('Paste ingredients'),
                ),
              );
              expect(find.text('Discard unapplied paste?'), findsOneWidget);
              await m.pages('editor-section-discard-paste-confirmation');
              await m.back();
              c.clearPaste();
            }
            if (state == 'populated') {
              await m.tap(find.text('Paste ingredients').first);
              await m.pages('paste-ingredients-dialog');
              await tester.enterText(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(TextField),
                ),
                '1 cup sugar\n2 chopped carrots',
              );
              FocusManager.instance.primaryFocus?.unfocus();
              repository.failPaste = true;
              await m.tap(find.text('Review'));
              expect(
                find.text(
                  'Could not review these ingredients. Your pasted text is still here. Try again.',
                ),
                findsOneWidget,
              );
              await m.pages('paste-ingredients-error');
              repository.failPaste = false;
              await m.tap(find.text('Review'));
              await m.pages('paste-ingredients-reviewed');
              await m.back();
              c.clearPaste();
              await m.tap(find.text('Paste steps'));
              await m.tap(find.text('Review'));
              expect(
                find.textContaining('Paste at least one step.'),
                findsOneWidget,
              );
              await m.pages('paste-steps-empty-error');
              await tester.enterText(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(TextField),
                ),
                '1. Heat the oil.\n2. Add the vegetables and simmer for 20 minutes.',
              );
              FocusManager.instance.primaryFocus?.unfocus();
              await m.tap(find.text('Review'));
              await m.pages('paste-steps-reviewed');
              await m.back();
              c.clearPaste();
              c.draft.title = '${c.draft.title} with an unsaved edit';
              c.changed();
              await m.tap(find.byTooltip('Back'));
              expect(find.text('Discard changes?'), findsOneWidget);
              await m.shot('editor-discard-confirmation');
              await m.back();
            }
            await tester.pumpWidget(const SizedBox.shrink());
            c.dispose();
          }
          await _editorSuggestionStates(m, prefs);
          for (final state in [
            'duplicate-one',
            'duplicate-many',
            'stale-original',
          ]) {
            final original = repository.recipes['0']!;
            if (state == 'duplicate-many') {
              repository.recipes['0'] = Recipe(
                id: original.id,
                favorite: original.favorite,
                revision: original.revision,
                createdAt: original.createdAt,
                updatedAt: '2026-10-09T20:10:12Z',
                fields: original.fields,
              );
              final fields = original.fields;
              repository.recipes['duplicate'] = Recipe(
                id: 'duplicate',
                favorite: false,
                revision: 1,
                createdAt: '2026-10-09T20:45:32Z',
                updatedAt: '2026-10-09T20:45:32Z',
                fields: RecipeFields(
                  title: fields.title,
                  description: 'The lighter stovetop version with white beans and tomatoes, ready for a quick weeknight supper.',
                  servings: fields.servings,
                  prepTime: fields.prepTime,
                  cookTime: fields.cookTime,
                  totalTime: fields.totalTime,
                  source: fields.source,
                  tags: fields.tags,
                  notes: fields.notes,
                  steps: fields.steps,
                  ingredients: const [
                    Ingredient(
                      amount: Amount.rational(numerator: 1, denominator: 1),
                      unit: 'cup',
                      name: 'white beans',
                      prepNote: '',
                      optional: false,
                      section: '',
                    ),
                    Ingredient(
                      amount: Amount.rational(numerator: 2, denominator: 1),
                      unit: '',
                      name: 'ripe tomatoes',
                      prepNote: 'chopped',
                      optional: false,
                      section: '',
                    ),
                  ],
                ),
              );
              await store.refresh();
            }
            final c = await EditorController.create(
              store: store,
              storage: MemoryDraftStorage(),
              base: state == 'stale-original' ? original : null,
              imported: state.startsWith('duplicate')
                  ? Candidate(
                      recipe: original,
                      warnings: const [],
                      ingredientSources: const [],
                    )
                  : null,
            );
            if (state == 'stale-original') {
              repository.recipes['0'] = Recipe(
                id: original.id,
                favorite: original.favorite,
                revision: original.revision + 1,
                createdAt: original.createdAt,
                updatedAt: '2026-10-10',
                fields: original.fields,
              );
              await store.refresh();
            }
            await m.mount(RecipeEditor(controller: c));
            await m.tap(find.text('Save'));
            if (state.startsWith('duplicate')) {
              expect(find.text('Recipe already exists'), findsOneWidget);
              await m.pages('editor-$state-dialog');
              await m.back();
            } else {
              expect(find.text('Save copy'), findsOneWidget);
              expect(c.draft.stale, isTrue);
              expect(c.draft.error, isNull);
              await m.pages('editor-stale-original');
            }
            await tester.pumpWidget(const SizedBox.shrink());
            c.dispose();
            repository.recipes.remove('duplicate');
            repository.recipes['0'] = original;
            await store.refresh();
          }

          final import = ImportController(
            service: service,
            storage: MemoryDraftStorage(),
            preferences: prefs,
          );
          await m.mount(
            ImportScreen(controller: import, onReview: (_, _) async => null),
          );
          for (final tab in ImportTab.values) {
            import.tab = tab;
            import.changed();
            await m.pages('import-${tab.name}-empty');
          }
          // Real Image.memory previews of a generated synthetic card. PNG
          // bytes are used only by the widget fixture; no provider sees them.
          late Uint8List photo;
          await tester.runAsync(() async {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            canvas.drawRect(
              const Rect.fromLTWH(0, 0, 120, 160),
              Paint()..color = const Color(0xfff4edda),
            );
            for (var i = 0; i < 7; i++) {
              canvas.drawLine(
                Offset(12, 20 + i * 18.0),
                Offset(108, 20 + i * 18.0),
                Paint()
                  ..color = const Color(0xff48674e)
                  ..strokeWidth = 2,
              );
            }
            final picture = recorder.endRecording();
            final image = await picture.toImage(120, 160);
            photo = (await image.toByteData(format: ui.ImageByteFormat.png))!
                .buffer
                .asUint8List();
            image.dispose();
            picture.dispose();
          });
          await tester.runAsync(
            () => precacheImage(
              MemoryImage(photo),
              tester.element(find.byType(ImportScreen)),
            ),
          );
          import.tab = ImportTab.photos;
          for (final count in [1, 8]) {
            import.photos.clear();
            for (var i = 0; i < count; i++) {
              import.photos.add(ImportPhoto(id: '$i', jpeg: photo));
            }
            import.changed();
            await m.pages('import-photos-$count');
          }
          import.photos.clear();
          import.tab = ImportTab.text;
          import.text =
              'Family supper\n1 lb pork\n2 carrots\nSimmer for 45 minutes.';
          import.changed();
          await m.pump();
          await tester.enterText(
            find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText == 'Paste recipe text',
            ),
            import.text,
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await m.tap(find.widgetWithText(FilledButton, 'Smart Import'));
          await m.pages('import-choose-candidate');
          await m.back();
          import.error = 'Google could not read this recipe page. Paste the text or try again.';
          import.changed(clearError: false);
          await m.pages('import-error');
          await m.tap(find.text('Smart Import settings'));
          await m.pages('import-smart-settings-dialog');
          await m.tap(find.text('View prompt'));
          await m.pages('import-view-prompt-dialog');
          await m.back();
          await m.tap(find.text('Last Smart Import'));
          await m.pages('import-diagnostic-dialog');
          await m.back();
          await m.back();
          import.busy = true;
          import.changed(clearError: false);
          await m.shot('import-loading');
          await tester.pumpWidget(const SizedBox.shrink());
          import.dispose();

          for (final state in ['key-saved', 'no-key', 'error', 'loading']) {
            service.platform.hasKey = state != 'no-key';
            service.platform.fail = state == 'error';
            service.platform.pending = state == 'loading'
                ? Completer<SmartImportSettings>()
                : null;
            await m.mount(
              SmartSettingsScreen(
                service: service,
                testKey: () async {},
                openUrl: (_) async {},
              ),
            );
            await m.pages('smart-settings-$state');
            if (state == 'key-saved') {
              await m.tap(find.text('View prompts'));
              await m.pages('smart-settings-prompts-dialog');
              await m.back();
              await m.tap(find.text('Last Smart Import'));
              await m.pages('smart-settings-diagnostic-dialog');
              await m.back();
              await m.tap(find.text('Remove key'));
              await m.shot('smart-settings-remove-key-confirmation');
              await m.back();
            }
          }
          service.platform.pending = null;
          service.platform.fail = false;
          await m.mount(
            HowCookdexWorksScreen(
              loadAppInfo: () async => 'cookdex dev · synthetic fixture',
              openUrl: (_) async {},
            ),
          );
          await m.pages('help-overview');
          for (final section in helpSections) {
            if (section.id != 'start') await m.tap(find.text(section.title));
            await m.pages('help-${section.id}');
            await m.tap(find.text(section.title));
          }

          final backend = FakeSyncBackend();
          final sync = SyncController(
            backend: backend,
            refreshRecipes: store.refresh,
            isAndroid: android,
            requestPermission: () async => true,
            currentGeneration: () => store.syncGeneration,
          );
          for (final state in [
            'loading',
            'empty',
            'one',
            'many',
            'synced-one',
            'synced-many',
            'long',
            'disabled',
            'error',
            'busy',
          ]) {
            backend.current = syncStatus(
              enabled: state != 'disabled',
              generation: store.syncGeneration,
              peers: [
                if (state != 'empty')
                  SyncPeer(
                    id: 'tablet',
                    name: state == 'long'
                        ? 'My Pixel Tablet kept on the kitchen counter for cooking and family recipes'
                        : 'Pixel Tablet',
                    address: '192.168.1.5:47832',
                    lastSync: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    caughtUp: state.startsWith('synced'),
                  ),
                if ([
                  'many',
                  'synced-many',
                  'long',
                  'error',
                  'busy',
                ].contains(state))
                  SyncPeer(
                    id: 'pc',
                    name: 'SYLPH-PC',
                    address: '192.168.1.6:47832',
                    lastSync: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                    caughtUp: state.startsWith('synced'),
                  ),
              ],
              reports: state == 'error'
                  ? const [
                      SyncReport(
                        id: 'pc',
                        name: 'SYLPH-PC',
                        status: 'error',
                        error:
                            'Connection rejected. Pairing trust did not match.',
                      ),
                    ]
                  : const [],
            );
            await sync.refresh();
            if (state == 'loading') sync.status = null;
            sync.busy = state == 'busy';
            await m.mount(SyncScreen(controller: sync, store: store));
            await m.pages('sync-$state');
            if (state.startsWith('synced')) {
              expect(find.text('Synced'), findsOneWidget);
            }
            if (state == 'many') {
              await m.tap(find.text('Technical details'));
              expect(find.text('Port'), findsOneWidget);
              await m.pages(
                'sync-technical-details',
                reset: false,
                note: 'Starts at expanded lower section to preserve the actual lazy ExpansionTile state.',
              );
              await m.tap(find.text('Phone <test>'));
              expect(find.text('Device name'), findsWidgets);
              await m.shot('sync-device-name-dialog');
              await m.back();
            }
            if (state == 'long') {
              await m.mount(
                SyncDeviceDetailsScreen(controller: sync, deviceId: 'tablet'),
              );
              await m.pages('device-details-long-name');
            }
          }
          sync.busy = false;
          await m.mount(
            SyncDeviceDetailsScreen(controller: sync, deviceId: 'tablet'),
          );
          await m.pages('device-details');
          await m.tap(find.text('Forget device'));
          await m.shot('forget-device-confirmation');
          await m.back();
          await sync.lifecycle(true);
          await m.mount(PairingScreen(controller: sync));
          await m.pages('pairing-choice');
          await m.tap(find.text('Invite a device').last);
          await m.pages('pairing-invite-empty');
          await m.tap(find.text('New invitation'));
          expect(find.byType(PrettyQrView), findsOneWidget);
          await m.pages('pairing-invite-code');
          await m.mount(
            PairingScreen(
              controller: sync,
              invitationAge: () => const Duration(minutes: 11),
            ),
          );
          await m.tap(find.text('Invite a device').last);
          await m.tap(find.text('New invitation'));
          expect(
            find.text('Invitation expired, used or revoked.'),
            findsOneWidget,
          );
          await m.pages('pairing-invite-expired');
          await m.tap(find.text('Choose another way'));
          await m.tap(find.text('Join a device').last);
          await m.pages('pairing-join');
          if (android) {
            const method = MethodChannel(
              'dev.steenbakker.mobile_scanner/scanner/method',
            );
            const event = MethodChannel(
              'dev.steenbakker.mobile_scanner/scanner/event',
            );
            const orientation = MethodChannel(
              'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
            );
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              method,
              (call) async => call.method == 'state'
                  ? 0
                  : call.method == 'request'
                  ? false
                  : null,
            );
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              event,
              (_) async => null,
            );
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              orientation,
              (_) async => null,
            );
            await m.tap(find.text('Scan QR code'));
            expect(find.text('Scan invitation'), findsOneWidget);
            await m.pump();
            expect(
              find.textContaining('Camera access is unavailable.'),
              findsOneWidget,
            );
            await m.shot('pairing-scanner-unavailable');
            await m.tap(find.text('Back to pairing'));
            addTearDown(() {
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                method,
                null,
              );
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                event,
                null,
              );
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                orientation,
                null,
              );
            });
            await m.tap(find.text('Paste invitation'));
          }
          await tester.enterText(
            find.byType(TextField),
            'recipe-pair:synthetic-test-code',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          expect(find.text('recipe-pair:synthetic-test-code'), findsOneWidget);
          await m.pages('pairing-join-paste');
          sync.error = 'The invitation has expired. Ask the other device for a new code.';
          sync.notifyListeners();
          await m.pages('pairing-error');
          sync.error = null;
          repository.heads = [
            Conflict(
              recipeId: '0',
              versions: [
                ConflictVersion(
                  id: 'phone-edit',
                  recipe: polishRecipe('0', _longTitle),
                ),
                ConflictVersion(
                  id: 'pc-edit',
                  recipe: polishRecipe('0', 'Family supper updated on PC'),
                ),
                const ConflictVersion(
                  id: 'tablet-delete',
                  deletedAt: '2026-10-09',
                ),
              ],
            ),
          ];
          await store.refresh();
          await m.mount(SyncScreen(controller: sync, store: store));
          await m.pages('sync-conflict');
          await m.mount(ConflictsScreen(controller: sync, store: store));
          await m.pages('conflicts-collapsed');
          await m.tap(find.textContaining('Version 1 ·').first);
          await m.pages('conflict-version-expanded');
          await m.tap(find.text('Use version').first);
          await m.pages('conflict-use-version-confirmation');
          await m.back();
          await m.tap(find.text('Version 3 · Deletion'));
          await m.pages('conflict-deletion-expanded');
          await m.tap(find.text('Use deletion').first);
          await m.pages('conflict-use-deletion-confirmation');
          await m.back();
          await m.tap(find.text('Keep all').first);
          await m.pages('conflict-keep-all-confirmation');
          await m.back();
          sync.busy = true;
          sync.notifyListeners();
          await m.pages('conflict-resolving');
          sync.busy = false;
          sync.error = 'Could not resolve this conflict. Your recipe versions are still here. Try again.';
          sync.notifyListeners();
          await m.pages('conflict-error');
          sync.error = null;
          final singleConflict = repository.heads.single;
          repository.heads = [
            for (var i = 0; i < 4; i++)
              Conflict(
                recipeId: 'conflict-$i',
                versions: singleConflict.versions,
              ),
          ];
          await store.refresh();
          await m.mount(ConflictsScreen(controller: sync, store: store));
          await m.pages('conflicts-many');
          repository.heads = [];
          await store.refresh();
          await m.pages('conflicts-empty');
          await tester.pumpWidget(const SizedBox.shrink());
          sync.dispose();

          // Native-only actions share this exact production confirmation
          // component. This covers their rendered dialogs while keeping Rust
          // state and all device data out of a visual fixture.
          for (final spec in [
            (
              'cleanup-preview',
              'Clean up 12 recipes?',
              'Clean up',
              'Normalize units, times and lowercase tags.\n2 conflicted recipes will be skipped.',
            ),
            (
              'recover-confirmation',
              'Recover previous save?',
              'Recover',
              'Restore the previous Flutter recipe collection and shopping list.',
            ),
          ]) {
            late BuildContext context;
            await m.mount(
              Builder(
                builder: (c) {
                  context = c;
                  return const Scaffold();
                },
              ),
            );
            unawaited(
              confirmCookdex(
                context,
                title: spec.$2,
                action: spec.$3,
                content: Text(spec.$4),
              ),
            );
            await m.shot(
              spec.$1,
              note: 'Production confirmation component and exact production text; native action callback not invoked.',
            );
            await m.back();
          }
          m.complete = true;
          await m.manifest();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          prefs.dispose();
          // Retain partial evidence if a later scenario fails.
          if (m.shots.isNotEmpty) await m.manifest();
        }
      }, timeout: const Timeout(Duration(minutes: 15)));
    }
  }
}
