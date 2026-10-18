import 'package:flutter/foundation.dart';

import 'recipe_store_test.dart' as fixtures;

import 'package:cookdex/ui/recipe_detail.dart';

import 'dart:async';

import 'package:cookdex/app_platform.dart';
import 'package:cookdex/draft_storage.dart';
import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/components.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform extends AppPlatform {
  _Platform({this.isAndroid = true, this.wallpaperSeed});
  Color? wallpaperSeed;
  final wallpaperCalls = <Brightness>[];
  Future<ColorScheme?> Function(Brightness)? wallpaperResponse;
  @override
  final bool isAndroid;
  int backgrounds = 0;
  int zipPickerCalls = 0;
  Uint8List? zipBytes;
  Completer<Uint8List?>? zipPickerGate;
  @override
  Future<void> backgroundTask() async {
    backgrounds++;
  }

  @override
  Future<void> openSource(String url) async {}
  @override
  Future<Uint8List?> pickRecipeZip() async {
    zipPickerCalls++;
    return zipPickerGate == null ? zipBytes : await zipPickerGate!.future;
  }

  @override
  Future<String> privateRoot() async => throw UnimplementedError();
  @override
  Future<void> setKeepScreenOn(bool enabled) async {}
  @override
  Future<ColorScheme?> wallpaperColorScheme({
    Brightness brightness = Brightness.dark,
  }) async {
    wallpaperCalls.add(brightness);
    if (wallpaperResponse != null) return wallpaperResponse!(brightness);
    return wallpaperSeed == null
        ? null
        : ColorScheme.fromSeed(
            seedColor: wallpaperSeed!,
            brightness: brightness,
          );
  }
}

class _Repository implements RecipeRepository {
  final events = StreamController<CollectionEvent>.broadcast();
  @override
  Future<CollectionSnapshot> snapshot() async => const CollectionSnapshot(
    setAsideCount: 0,
    shoppingCategories: [ShoppingCategory(id: 'other', name: 'Other')],
    generation: 0,
    summaries: [],
    shopping: [],
    conflicts: [],
    hasPrevious: false,
  );
  @override
  Stream<CollectionEvent> subscribe() => events.stream;
  @override
  Future<Recipe?> detail(String id) async => null;
  @override
  Future<List<String>> ingredientAmounts(List<Ingredient> ingredients) async =>
      [];
  @override
  Future<CollectionSnapshot> favorite(
    int generation,
    String id,
    bool value,
  ) async => snapshot();
  @override
  Future<CollectionSnapshot> delete(int generation, String id) async =>
      snapshot();
  @override
  Future<BackupPreview> previewRestore(Uint8List bytes) async =>
      throw UnimplementedError();
  @override
  Future<CollectionSnapshot> restore(BackupPreview preview) async => snapshot();
  @override
  Future<void> close() async {
    await events.close();
  }
}

class _RestoreRepository extends _Repository {
  int previewCalls = 0, restoreCalls = 0;
  Uint8List? previewBytes;

  @override
  Future<BackupPreview> previewRestore(Uint8List bytes) async {
    previewCalls++;
    previewBytes = bytes;
    return const BackupPreview(
      RestoreReport(
        shoppingSetup: false,
        added: 3,
        updated: 1,
        skipped: 2,
        conflicts: [],
      ),
      'synthetic-preview',
    );
  }

  @override
  Future<CollectionSnapshot> restore(BackupPreview preview) async {
    restoreCalls++;
    return snapshot();
  }
}

void main() {
  Future<void> mountWallpaperApp(
    WidgetTester tester,
    LocalPreferences preferences,
    _Platform platform,
  ) async {
    final store = RecipeStore(_Repository(), preferences);
    await store.initialize();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    });
    await tester.pumpWidget(CookdexApp(store: store, platform: platform));
    await tester.pumpAndSettle();
  }

  ColorScheme currentScheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;

  Future<void> resumeApp(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  void expectWallpaperRefreshes(_Platform platform, int count) {
    expect(
      platform.wallpaperCalls.where((value) => value == Brightness.light),
      hasLength(count),
    );
    expect(
      platform.wallpaperCalls.where((value) => value == Brightness.dark),
      hasLength(count),
    );
  }

  testWidgets('wallpaper refreshes on enable, not unrelated preferences', (
    tester,
  ) async {
    const firstSeed = Color(0xff925ca3);
    const nextSeed = Color(0xff327d58);
    final preferences = LocalPreferences.memory()
      ..setThemeMode(ThemeMode.dark)
      ..setWallpaperColors(true);
    final platform = _Platform(wallpaperSeed: firstSeed);
    await mountWallpaperApp(tester, preferences, platform);
    expectWallpaperRefreshes(platform, 1);
    preferences.setThemeMode(ThemeMode.light);
    preferences.setFavoritesOnly(true);
    preferences.setRecipeTextSize(RecipeTextSize.extraLarge);
    await tester.pumpAndSettle();
    expectWallpaperRefreshes(platform, 1);
    preferences.setWallpaperColors(false);
    await tester.pumpAndSettle();
    expect(currentScheme(tester), cookdexLightColors);
    platform.wallpaperSeed = nextSeed;
    preferences.setWallpaperColors(true);
    await tester.pumpAndSettle();
    expectWallpaperRefreshes(platform, 2);
    expect(
      currentScheme(tester),
      ColorScheme.fromSeed(seedColor: nextSeed, brightness: Brightness.light),
    );
    preferences.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(
      currentScheme(tester),
      ColorScheme.fromSeed(seedColor: nextSeed, brightness: Brightness.dark),
    );
    expectWallpaperRefreshes(platform, 2);
  });

  for (final initialResult in ['success', 'unavailable', 'error']) {
    testWidgets('resume refreshes wallpaper after $initialResult', (
      tester,
    ) async {
      const nextSeed = Color(0xff327d58);
      final preferences = LocalPreferences.memory()
        ..setThemeMode(ThemeMode.dark)
        ..setWallpaperColors(true);
      final platform = _Platform(
        wallpaperSeed: initialResult == 'success'
            ? const Color(0xff925ca3)
            : null,
      );
      if (initialResult == 'error') {
        platform.wallpaperResponse = (_) async =>
            throw PlatformException(code: 'wallpaper_unavailable');
      }
      await mountWallpaperApp(tester, preferences, platform);
      expectWallpaperRefreshes(platform, 1);
      expect(tester.takeException(), isNull);
      if (initialResult != 'success') {
        expect(currentScheme(tester), cookdexColors);
      }
      platform.wallpaperResponse = null;
      platform.wallpaperSeed = nextSeed;
      await resumeApp(tester);
      expectWallpaperRefreshes(platform, 2);
      expect(
        currentScheme(tester),
        ColorScheme.fromSeed(seedColor: nextSeed, brightness: Brightness.dark),
      );
      preferences.setWallpaperColors(false);
      await tester.pumpAndSettle();
      await resumeApp(tester);
      expectWallpaperRefreshes(platform, 2);
      expect(currentScheme(tester), cookdexColors);
    });
  }

  for (final disableBeforeCompletion in [false, true]) {
    testWidgets(
      disableBeforeCompletion
          ? 'disabled wallpaper ignores pending refresh completion'
          : 'new wallpaper refresh wins against older pending results',
      (tester) async {
        const oldSeed = Color(0xff925ca3);
        const newSeed = Color(0xff327d58);
        final pending = {
          for (final brightness in Brightness.values)
            brightness: Completer<ColorScheme?>(),
        };
        final preferences = LocalPreferences.memory()
          ..setThemeMode(ThemeMode.dark)
          ..setWallpaperColors(true);
        final platform = _Platform(wallpaperSeed: newSeed)
          ..wallpaperResponse = (brightness) => pending[brightness]!.future;
        await mountWallpaperApp(tester, preferences, platform);
        expectWallpaperRefreshes(platform, 1);
        if (disableBeforeCompletion) {
          preferences.setWallpaperColors(false);
          await tester.pumpAndSettle();
        } else {
          platform.wallpaperResponse = null;
          await resumeApp(tester);
          expectWallpaperRefreshes(platform, 2);
          expect(
            currentScheme(tester),
            ColorScheme.fromSeed(
              seedColor: newSeed,
              brightness: Brightness.dark,
            ),
          );
        }
        for (final entry in pending.entries) {
          entry.value.complete(
            ColorScheme.fromSeed(seedColor: oldSeed, brightness: entry.key),
          );
        }
        await tester.pumpAndSettle();
        for (final mode in [ThemeMode.dark, ThemeMode.light]) {
          preferences.setThemeMode(mode);
          await tester.pumpAndSettle();
          final dark = mode == ThemeMode.dark;
          expect(
            currentScheme(tester),
            disableBeforeCompletion
                ? (dark ? cookdexColors : cookdexLightColors)
                : ColorScheme.fromSeed(
                    seedColor: newSeed,
                    brightness: dark ? Brightness.dark : Brightness.light,
                  ),
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'wallpaper colors match Light and Dark and fall back when disabled',
    (tester) async {
      const seed = Color(0xff925ca3);
      final preferences = LocalPreferences.memory()..setWallpaperColors(true);
      final store = RecipeStore(_Repository(), preferences);
      await store.initialize();
      await tester.pumpWidget(
        CookdexApp(
          store: store,
          platform: _Platform(wallpaperSeed: seed),
        ),
      );
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        preferences.setThemeMode(mode);
        await tester.pumpAndSettle();
        final scheme = Theme.of(tester.element(find.byType(Scaffold).first))
            .colorScheme;
        final brightness = mode == ThemeMode.light
            ? Brightness.light
            : Brightness.dark;
        expect(
          scheme,
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
        );
      }
      preferences.setWallpaperColors(false);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme,
        cookdexColors,
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      preferences.dispose();
    },
  );

  testWidgets('System follows brightness while explicit themes override it', (
    tester,
  ) async {
    final preferences = LocalPreferences.memory();
    final store = RecipeStore(_Repository(), preferences);
    await store.initialize();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(CookdexApp(store: store, platform: _Platform()));
    await tester.pumpAndSettle();
    ColorScheme scheme() =>
        Theme.of(tester.element(find.byType(Scaffold).first)).colorScheme;
    expect(scheme().surface, cookdexLightColors.surface);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(scheme().surface, cookdexColors.surface);
    preferences.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(scheme().surface, cookdexLightColors.surface);
    preferences.setThemeMode(ThemeMode.dark);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(scheme().surface, cookdexColors.surface);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    preferences.dispose();
  });

  testWidgets('empty restore shortcut serializes a pending picker', (
    tester,
  ) async {
    final preferences = LocalPreferences.memory();
    final store = RecipeStore(_Repository(), preferences);
    final platform = _Platform()..zipPickerGate = Completer<Uint8List?>();
    await store.initialize();
    await tester.pumpWidget(CookdexApp(store: store, platform: platform));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore a backup'));
    await tester.pump();
    await tester.tap(find.text('Restore a backup'));
    await tester.pump();
    expect(platform.zipPickerCalls, 1);
    platform.zipPickerGate!.complete(null);
    await tester.pumpAndSettle();
    platform.zipPickerGate = null;
    await tester.tap(find.text('Restore a backup'));
    await tester.pumpAndSettle();
    expect(platform.zipPickerCalls, 2);
    expect(find.text('No recipes caught yet'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    preferences.dispose();
  });
  testWidgets(
    'actual nested recipe route previews Back and inactive tabs retain it',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final preferences = LocalPreferences.memory();
      final store = RecipeStore(
        fixtures.FakeRepository([fixtures.recipe('a')]),
        preferences,
      );
      await store.initialize();
      await tester.pumpWidget(CookdexApp(store: store, platform: _Platform()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lemon cake').first);
      await tester.pumpAndSettle();
      final route = ModalRoute.of(tester.element(find.byType(RecipeDetail)))!;
      expect(route.isFirst, false);
      await tester.tap(find.byKey(const Key('recipe-scale-toggle')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('recipe-scale-2')).hitTestable(),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsOneWidget);
      expect(
        find.byKey(const Key('recipe-scale-2')).hitTestable(),
        findsNothing,
      );
      Future<void> gesture(String method, [double? progress]) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/backgesture',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(
              method,
              progress == null
                  ? null
                  : {
                      'touchOffset': <double>[5 + 250 * progress, 300],
                      'progress': progress,
                      'swipeEdge': 0,
                    },
            ),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await gesture('startBackGesture', 0);
      await gesture('updateBackGestureProgress', .4);
      expect(route.animation!.value, lessThan(1));
      await gesture('cancelBackGesture');
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsOneWidget);
      await tester.tap(find.text('Shopping list').last);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsOneWidget);
      await gesture('startBackGesture', 0);
      await gesture('commitBackGesture');
      await tester.pumpAndSettle();
      expect(find.byType(RecipeDetail), findsNothing);
      expect(find.text('Lemon cake'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      preferences.dispose();
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('unreadable draft can be retained or discarded before writing', (
    tester,
  ) async {
    final preferences = LocalPreferences.memory();
    final store = RecipeStore(_Repository(), preferences);
    final drafts = MemoryDraftStorage();
    await drafts.write({'version': -1});
    await store.initialize();
    await tester.pumpWidget(
      CookdexApp(store: store, platform: _Platform(), drafts: drafts),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Write a recipe').first);
    await tester.pumpAndSettle();
    expect(find.text('Discard unreadable draft?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await drafts.read(), {'version': -1});
    await tester.tap(find.text('Write a recipe').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    expect(await drafts.read(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    preferences.dispose();
  });

  testWidgets(
    'sheet is capped, content sized, and Escape dismisses before root Back',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: cookdexTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showCookdexSheet<void>(
                  context,
                  child: const ListTile(title: Text('One action')),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final sheet = tester.getRect(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(sheet.width, lessThanOrEqualTo(560));
      expect(sheet.height, lessThan(250));
      expect(sheet.center.dx, closeTo(550, 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('One action'), findsNothing);
    },
  );

  testWidgets(
    'Android tabs, overlay Back, system root exit, wallpaper off and IME navigation',
    (tester) async {
      var systemPops = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'SystemNavigator.pop') systemPops++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final preferences = LocalPreferences.memory();
      final repo = _Repository();
      final store = RecipeStore(repo, preferences);
      final platform = _Platform();
      await store.initialize();
      await tester.pumpWidget(CookdexApp(store: store, platform: platform));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(SwitchListTile, 'Wallpaper colors'),
        350,
        scrollable: find.descendant(
          of: find.byKey(const PageStorageKey('settings')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Wallpaper colors'),
            )
            .value,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        0,
      );
      expect(platform.backgrounds, 0);
      expect(systemPops, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(platform.backgrounds, 0);
      expect(systemPops, 1);

      await tester.tap(find.text('Write a recipe').first);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Write a recipe'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(
        tester.binding.focusManager.primaryFocus?.context?.widget
            is EditableText,
        isFalse,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      tester.view.resetViewInsets();
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    },
  );

  for (final chooseZip in [false, true]) {
    testWidgets(
      'empty library Restore a backup routes through ${chooseZip ? 'preview cancellation' : 'picker cancellation'}',
      (tester) async {
        final preferences = LocalPreferences.memory();
        final repository = _RestoreRepository();
        final store = RecipeStore(repository, preferences);
        final platform = _Platform()
          ..zipBytes = chooseZip ? Uint8List.fromList([1, 2, 3, 4]) : null;
        await store.initialize();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          preferences.dispose();
        });
        await tester.pumpWidget(CookdexApp(store: store, platform: platform));
        await tester.pumpAndSettle();
        expect(find.text('No recipes caught yet'), findsOneWidget);
        final beforeGeneration = store.generation;
        await tester.tap(find.widgetWithText(TextButton, 'Restore a backup'));
        await tester.pumpAndSettle();
        expect(platform.zipPickerCalls, 1);
        expect(repository.previewCalls, chooseZip ? 1 : 0);
        if (chooseZip) {
          expect(repository.previewBytes, orderedEquals([1, 2, 3, 4]));
          expect(find.text('Restore recipe ZIP?'), findsOneWidget);
          expect(find.text('3 new · 1 updated · 2 skipped'), findsOneWidget);
          await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
          await tester.pumpAndSettle();
        }
        expect(repository.restoreCalls, 0);
        expect(store.generation, beforeGeneration);
        expect(store.summaries, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('No recipes caught yet'), findsOneWidget);
        expect(
          find.widgetWithText(TextButton, 'Restore a backup').hitTestable(),
          findsOneWidget,
        );
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          0,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('wallpaper preference is hidden on Windows', (tester) async {
    final preferences = LocalPreferences.memory();
    final store = RecipeStore(_Repository(), preferences);
    await store.initialize();
    await tester.pumpWidget(
      CookdexApp(store: store, platform: _Platform(isAndroid: false)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Wallpaper colors'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    preferences.dispose();
  });
}
