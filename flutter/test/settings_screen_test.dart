import 'package:cookdex/ui/settings_screen.dart';
import 'package:cookdex/settings_platform.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _actions = [
  'Sync settings',
  'Download recipe ZIP',
  'Save readable cookbook',
  'Restore recipe ZIP',
  'Recover previous save',
  'Clean up recipes',
  'Smart Import settings',
  'How cookdex works',
  'cookdex on GitHub',
  'Share cookdex',
];

SettingsScreen _screen({
  bool hasPrevious = true,
  bool busy = false,
  bool isAndroid = true,
  void Function(String)? onAction,
  bool shoppingKeepAwake = false,
  ValueChanged<bool>? onShoppingKeepAwake,
  double recipeTextScale = 1,
  ValueChanged<double>? onRecipeTextScale,
  ThemeMode themeMode = ThemeMode.system,
  ValueChanged<ThemeMode>? onThemeMode,
  bool wallpaperColors = false,
  ValueChanged<bool>? onWallpaperColors,
  Future<String>? installedVersion,
}) {
  VoidCallback? action(String label) =>
      onAction == null ? null : () => onAction(label);
  return SettingsScreen(
    hasPrevious: hasPrevious,
    busy: busy,
    syncSummary: 'Kitchen phone · Last synced today',
    onSync: action('Sync settings'),
    onDownloadRecipeZip: action('Download recipe ZIP'),
    onSaveReadableCookbook: action('Save readable cookbook'),
    onRestoreRecipeZip: action('Restore recipe ZIP'),
    onRecoverPreviousSave: action('Recover previous save'),
    onCleanUpRecipes: action('Clean up recipes'),
    onSmartImportSettings: action('Smart Import settings'),
    onHowCookdexWorks: action('How cookdex works'),
    onGitHub: action('cookdex on GitHub'),
    onShareCookdex: action('Share cookdex'),
    shoppingKeepAwake: shoppingKeepAwake,
    onShoppingKeepAwake: onShoppingKeepAwake ?? (_) {},
    recipeTextScale: recipeTextScale,
    onRecipeTextScale: onRecipeTextScale ?? (_) {},
    isAndroid: isAndroid,
    themeMode: themeMode,
    onThemeMode: onThemeMode,
    wallpaperColors: wallpaperColors,
    onWallpaperColors: onWallpaperColors ?? (_) {},
    version: '0.9.0+9001',
    installedVersion: installedVersion,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(400, 800),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
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
      home: child,
    ),
  );
}

Future<void> _reveal(WidgetTester tester, String label) async {
  final scrollable = find.descendant(
    of: find.byKey(const PageStorageKey('settings')),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(
    find.text(label),
    160,
    scrollable: scrollable,
  );
  await tester.pumpAndSettle();
}

ListTile _tile(WidgetTester tester, String label) => tester.widget<ListTile>(
  find.ancestor(of: find.text(label), matching: find.byType(ListTile)).first,
);

void main() {
  testWidgets('Theme offers System, Light and Dark and returns the choice', (
    tester,
  ) async {
    ThemeMode? chosen;
    await _pump(tester, _screen(onThemeMode: (value) => chosen = value));
    await _reveal(tester, 'Theme');
    expect(find.text('System'), findsOneWidget);
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(chosen, ThemeMode.light);
  });

  testWidgets('About uses the installed package version after async load', (
    tester,
  ) async {
    const channel = MethodChannel('com.sylph.cookdex.dev/platform');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return '1.2.3+12345';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await _pump(
      tester,
      _screen(installedVersion: SettingsPlatform().appVersion()),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, '1.2.3+12345');
    expect(find.text('1.2.3+12345'), findsOneWidget);
    expect(find.text('0.9.0+9001'), findsNothing);
    expect(calls, ['appVersion']);
  });

  testWidgets('unavailable package metadata never shows a stale version', (
    tester,
  ) async {
    const channel = MethodChannel('com.sylph.cookdex.dev/platform');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      throw PlatformException(code: 'unavailable');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await _pump(
      tester,
      _screen(installedVersion: SettingsPlatform().appVersion()),
    );
    await tester.pumpAndSettle();
    await _reveal(tester, 'Version unavailable');
    expect(find.text('Version unavailable'), findsOneWidget);
    expect(find.text('0.9.0+9001'), findsNothing);
  });

  testWidgets('settings groups, labels, version and privacy are accurate', (
    tester,
  ) async {
    await _pump(tester, _screen());
    for (final label in [
      'Settings',
      'Sync',
      'Kitchen phone · Last synced today',
      'Backup & restore',
      ..._actions.skip(1),
      'Smart Import',
      'Shopping list',
      'Keep shopping screen awake',
      'Appearance',
      'Recipe text size',
      'Wallpaper colors',
      'About',
      'cookdex',
      '0.9.0+9001',
    ]) {
      await _reveal(tester, label);
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.text(
        'Recipes stay on your devices. Optional encrypted LAN sync '
        'connects paired devices. When you use Smart Import with AI, '
        'selected inputs are sent to Google. Link imports contact '
        'recipe websites.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every settings action invokes its supplied callback', (
    tester,
  ) async {
    final calls = <String>[];
    await _pump(tester, _screen(onAction: calls.add));
    for (final label in _actions) {
      await _reveal(tester, label);
      expect(_tile(tester, label).enabled, isTrue);
      await tester.tap(find.text(label));
      await tester.pump();
    }
    expect(calls, _actions);
  });

  testWidgets('missing callbacks and absent previous save disable actions', (
    tester,
  ) async {
    await _pump(tester, _screen());
    for (final label in _actions) {
      await _reveal(tester, label);
      expect(_tile(tester, label).enabled, isFalse);
      expect(_tile(tester, label).onTap, isNull);
    }
    final calls = <String>[];
    await _pump(tester, _screen(hasPrevious: false, onAction: calls.add));
    await _reveal(tester, 'Recover previous save');
    expect(find.text('No previous save'), findsOneWidget);
    expect(_tile(tester, 'Recover previous save').onTap, isNull);
    await tester.tap(find.text('Recover previous save'));
    expect(calls, isEmpty);
  });

  testWidgets('busy disables actions and preference controls', (tester) async {
    await _pump(tester, _screen(busy: true, onAction: (_) {}));
    for (final label in [..._actions, 'Recipe text size']) {
      await _reveal(tester, label);
      expect(_tile(tester, label).onTap, isNull);
    }
    for (final label in ['Keep shopping screen awake', 'Wallpaper colors']) {
      await _reveal(tester, label);
      final switchTile = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(switchTile.onChanged, isNull);
    }
  });

  testWidgets('preference controls call back and show new values', (
    tester,
  ) async {
    var keepAwake = false;
    var wallpaper = false;
    var scale = 1.0;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => _screen(
          shoppingKeepAwake: keepAwake,
          onShoppingKeepAwake: (value) => setState(() => keepAwake = value),
          wallpaperColors: wallpaper,
          onWallpaperColors: (value) => setState(() => wallpaper = value),
          recipeTextScale: scale,
          onRecipeTextScale: (value) => setState(() => scale = value),
        ),
      ),
    );
    await _reveal(tester, 'Keep shopping screen awake');
    await tester.tap(find.text('Keep shopping screen awake'));
    await tester.pumpAndSettle();
    expect(keepAwake, isTrue);
    await _reveal(tester, 'Wallpaper colors');
    await tester.tap(find.text('Wallpaper colors'));
    await tester.pumpAndSettle();
    expect(wallpaper, isTrue);
    for (final entry in {
      1.15: 'Large',
      1.3: 'Extra large',
      1.0: 'Default',
    }.entries) {
      await _reveal(tester, 'Recipe text size');
      await tester.tap(find.text('Recipe text size'));
      await tester.pumpAndSettle();
      for (final label in ['Default', 'Large', 'Extra large']) {
        expect(find.text(label).last, findsOneWidget);
      }
      await tester.tap(find.text(entry.value).last);
      await tester.pumpAndSettle();
      expect(scale, entry.key);
      expect(_tile(tester, 'Recipe text size').subtitle, isA<Text>());
      expect(
        (_tile(tester, 'Recipe text size').subtitle! as Text).data,
        entry.value,
      );
    }
  });

  testWidgets('Windows hides wallpaper colors', (tester) async {
    await _pump(tester, _screen(isAndroid: false));
    await _reveal(tester, 'Appearance');
    expect(find.text('Recipe text size'), findsOneWidget);
    expect(find.text('Wallpaper colors'), findsNothing);
  });

  testWidgets('320dp with double text wraps and keeps all settings reachable', (
    tester,
  ) async {
    await _pump(
      tester,
      _screen(onAction: (_) {}),
      size: const Size(320, 720),
      textScale: 2,
    );
    for (final label in [
      ..._actions,
      'Keep shopping screen awake',
      'Recipe text size',
      'Wallpaper colors',
      'About',
      '0.9.0+9001',
    ]) {
      await _reveal(tester, label);
      expect(tester.takeException(), isNull, reason: label);
    }
    await _reveal(tester, 'Recipe text size');
    await tester.tap(find.text('Recipe text size'));
    await tester.pumpAndSettle();
    expect(find.text('Extra large'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Extra large'));
    await tester.pumpAndSettle();
    expect(find.text('Extra large'), findsNothing);
  });
}
