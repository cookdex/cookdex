import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'app_platform.dart';
import 'app_identity.dart';
import 'bridge_loader.dart';
import 'draft_storage.dart';
import 'local_preferences.dart';
import 'recipe_store.dart';
import 'src/rust/api.dart';
import 'ui/app.dart';
import 'settings_platform.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Owner-selected shipping feel. Profiling config stays separate from delivery.
  if (Platform.isAndroid) {
    GestureBinding.instance.resamplingEnabled = true;
    GestureBinding.instance.samplingOffset = const Duration(milliseconds: -16);
  }
  final platform = NativeAppPlatform();
  try {
    await platform.verifyIdentity();
    await initializeBridge();
    const development = isDevelopment;
    final dataArg = args
        .where((a) => a.startsWith('--dev-data-dir='))
        .firstOrNull;
    final portArg = args
        .where((a) => a.startsWith('--dev-sync-port='))
        .firstOrNull;
    if ((!development || !Platform.isWindows) &&
        (dataArg != null || portArg != null)) {
      throw StateError('Development switches are Windows-only.');
    }
    final root = dataArg == null
        ? await platform.privateRoot()
        : dataArg.substring('--dev-data-dir='.length);
    if (dataArg != null && !RegExp(r'^[A-Za-z]:[/\\]').hasMatch(root)) {
      throw StateError('Development data path must be absolute.');
    }
    await Directory(root).create(recursive: true);
    final preferences = await LocalPreferences.load(
      '$root/ui-preferences.json',
    );
    final session = await CoreSession.openWithSyncPort(
      privateRoot: root,
      port: portArg == null
          ? null
          : int.parse(portArg.substring('--dev-sync-port='.length)),
    );
    final sync = await session.syncStatus();
    if (sync.name == 'Android device' || sync.name == 'Windows PC') {
      await session.syncConfigure(
        enabled: sync.enabled,
        name: await SettingsPlatform().deviceName(),
      );
    }
    final store = RecipeStore(RustRecipeRepository(session), preferences);
    await store.initialize();
    runApp(
      CookdexApp(
        store: store,
        platform: platform,
        drafts: FileDraftStorage('$root/editor-draft.json'),
        importDrafts: FileDraftStorage(
          '$root/import-draft.json',
          limitBytes: 16 * 1024 * 1024,
        ),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '$appName could not open its private storage. Close the app and try again.',
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
