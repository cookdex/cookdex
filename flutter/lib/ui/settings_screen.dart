import 'pixel_scroll.dart';
import 'retained_screen.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../help_content.dart';
import 'components.dart';

/// Presentation only: the shell owns persistence, services and confirmations.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.hasPrevious,
    this.busy = false,
    required this.syncSummary,
    this.syncChanges,
    this.readSyncSummary,
    this.onSync,
    this.onDownloadRecipeZip,
    this.onSaveReadableCookbook,
    this.onRestoreRecipeZip,
    this.onRecoverPreviousSave,
    this.onSnapshots,
    this.snapshotsFailing = false,
    this.onCleanUpRecipes,
    this.onSmartImportSettings,
    this.onHowCookdexWorks,
    required this.shoppingKeepAwake,
    required this.onShoppingKeepAwake,
    required this.recipeTextScale,
    required this.onRecipeTextScale,
    required this.isAndroid,
    this.themeMode = ThemeMode.system,
    this.onThemeMode,
    required this.wallpaperColors,
    required this.onWallpaperColors,
    required this.version,
    this.installedVersion,
  });

  final bool hasPrevious;
  final bool busy;
  final String syncSummary;
  final Listenable? syncChanges;
  final String Function()? readSyncSummary;
  final VoidCallback? onSync;
  final VoidCallback? onDownloadRecipeZip;
  final VoidCallback? onSaveReadableCookbook;
  final VoidCallback? onRestoreRecipeZip;
  final VoidCallback? onRecoverPreviousSave;
  final VoidCallback? onSnapshots;
  final bool snapshotsFailing;
  final VoidCallback? onCleanUpRecipes;
  final VoidCallback? onSmartImportSettings;
  final VoidCallback? onHowCookdexWorks;
  final bool shoppingKeepAwake;
  final ValueChanged<bool> onShoppingKeepAwake;
  final double recipeTextScale;
  final ValueChanged<double> onRecipeTextScale;
  final bool isAndroid;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeMode;
  final bool wallpaperColors;
  final ValueChanged<bool> onWallpaperColors;
  final String version;
  final Future<String>? installedVersion;

  static final _textSizes = <double, String>{
    1.0: 'Default',
    1.15: 'Large',
    1.3: 'Extra large',
  };

  static const _themes = {
    ThemeMode.system: 'System',
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
  };

  Future<void> _chooseTheme(BuildContext context) async {
    final choice = await showCookdexSheet<ThemeMode>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Theme',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final entry in _themes.entries)
            ListTile(
              title: Text(entry.value),
              selected: themeMode == entry.key,
              trailing: themeMode == entry.key
                  ? const Icon(Symbols.check)
                  : null,
              minVerticalPadding: 12,
              onTap: () => Navigator.of(context).pop(entry.key),
            ),
        ],
      ),
    );
    if (choice != null) onThemeMode?.call(choice);
  }

  Future<void> _chooseTextSize(BuildContext context) async {
    final choice = await showCookdexSheet<double>(
      context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Recipe text size',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          for (final entry in _textSizes.entries)
            ListTile(
              title: Text(entry.value),
              selected: recipeTextScale == entry.key,
              trailing: recipeTextScale == entry.key
                  ? const Icon(Symbols.check)
                  : null,
              minVerticalPadding: 12,
              onTap: () => Navigator.of(context).pop(entry.key),
            ),
        ],
      ),
    );
    if (choice != null && context.mounted) onRecipeTextScale(choice);
  }

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? callback, {
    String? summary,
    bool available = true,
  }) {
    final enabled = !busy && available && callback != null;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: summary == null ? null : Text(summary),
      trailing: const Icon(Symbols.chevron_right),
      minVerticalPadding: 12,
      enabled: enabled,
      onTap: enabled ? callback : null,
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(),
                    children[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Widget _preferenceToggle({
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      final painter = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      var longestWord = 0.0;
      for (final word in label.split(' ')) {
        painter.text = TextSpan(
          text: word,
          style: Theme.of(context).textTheme.bodyLarge,
        );
        painter.layout();
        if (painter.width > longestWord) longestWord = painter.width;
      }
      painter.dispose();
      // Keep the native switch tile's semantics and whole-row tap. Omit only
      // the decorative icon when its 56dp slot would split a complete word.
      // Remaining space reserves 32dp padding and the 60dp switch + 16dp gap.
      final showIcon = longestWord <= constraints.maxWidth - 32 - 76 - 56;
      return SwitchListTile(
        secondary: showIcon ? Icon(icon) : null,
        title: Text(label),
        value: value,
        onChanged: busy ? null : onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: SafeArea(
      top: false,
      child: PixelListView(
        key: const PageStorageKey('settings'),
        padding: const EdgeInsets.all(16),
        children: [
          _group(context, 'Sync', [
            VisibleListenableBuilder(
              listenable: syncChanges,
              builder: (_) => _action(
                'Sync settings',
                Symbols.sync,
                onSync,
                summary: readSyncSummary?.call() ?? syncSummary,
              ),
            ),
          ]),
          _group(context, 'Backup & restore', [
            _action(
              'Download recipe ZIP',
              Symbols.folder_zip,
              onDownloadRecipeZip,
            ),
            _action(
              'Save readable cookbook',
              Symbols.menu_book,
              onSaveReadableCookbook,
            ),
            _action(
              'Restore recipe ZIP',
              Symbols.upload_file,
              onRestoreRecipeZip,
            ),
            _action(
              'Recover previous save',
              Symbols.history,
              onRecoverPreviousSave,
              available: hasPrevious,
              summary: hasPrevious ? null : 'No previous save',
            ),
            _action(
              'Snapshots',
              Symbols.history,
              onSnapshots,
              summary: snapshotsFailing
                  ? 'Automatic snapshots have not been saving'
                  : 'Automatic backups on this device',
            ),
            _action(
              'Clean up recipes',
              Symbols.cleaning_services,
              onCleanUpRecipes,
            ),
          ]),
          _group(context, 'Smart Import', [
            _action(
              'Smart Import settings',
              Symbols.auto_awesome,
              onSmartImportSettings,
            ),
          ]),
          _group(context, 'Shopping list', [
            _preferenceToggle(
              icon: Symbols.light_mode,
              label: 'Keep shopping screen awake',
              value: shoppingKeepAwake,
              onChanged: onShoppingKeepAwake,
            ),
          ]),
          _group(context, 'Appearance', [
            _action(
              'Recipe text size',
              Symbols.text_fields,
              () => _chooseTextSize(context),
              summary: _textSizes[recipeTextScale] ?? 'Default',
            ),
            _action(
              'Theme',
              Symbols.brightness_6,
              () => _chooseTheme(context),
              summary: _themes[themeMode],
            ),
            if (isAndroid)
              _preferenceToggle(
                icon: Symbols.palette,
                label: 'Wallpaper colors',
                value: wallpaperColors,
                onChanged: onWallpaperColors,
              ),
          ]),
          _group(context, 'Help', [
            _action(helpTitle, Symbols.help, onHowCookdexWorks),
          ]),
          _group(context, 'About', [
            ListTile(
              leading: const Icon(Symbols.info),
              title: const Text('cookdex'),
              subtitle: installedVersion == null
                  ? Text(version)
                  : FutureBuilder<String>(
                      future: installedVersion,
                      builder: (context, snapshot) => Text(
                        snapshot.hasError
                            ? 'Version unavailable'
                            : snapshot.data ?? 'Loading version…',
                      ),
                    ),
              minVerticalPadding: 12,
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Recipes stay on your devices. Optional encrypted LAN sync '
                'connects paired devices. When you use Smart Import with AI, '
                'selected inputs are sent to Google. Link imports contact '
                'recipe websites.',
              ),
            ),
          ]),
        ],
      ),
    ),
  );
}
