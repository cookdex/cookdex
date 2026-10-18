import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'import_platform.dart';
import 'app_identity.dart';

class SettingsPlatform {
  static const _platform = MethodChannel('com.sylph.cookdex.dev/platform');
  static const _export = MethodChannel('com.sylph.cookdex.dev/export');

  /// Installed package metadata; never fall back to a manually maintained build.
  Future<String> appVersion() async {
    try {
      final version = await _platform.invokeMethod<String>('appVersion');
      return version == null || version.isEmpty
          ? 'Version unavailable'
          : version;
    } on MissingPluginException {
      return 'Version unavailable';
    } on PlatformException {
      return 'Version unavailable';
    }
  }

  Future<String> deviceName() async => Platform.isAndroid
      ? (await _platform.invokeMethod<String>('deviceName'))!
      : Platform.localHostname;
  Future<String> appInfo() async => Platform.isAndroid
      ? (await _platform.invokeMethod<String>('appInfo'))!
      : '$appName\nVersion: ${await appVersion()}\nDevice: ${Platform.localHostname}\nWindows: ${Platform.operatingSystemVersion}';
  Future<bool> hasLocalNetwork() async =>
      !Platform.isAndroid ||
      await _platform.invokeMethod<bool>('hasLocalNetwork') == true;
  Future<bool> requestLocalNetwork() async =>
      !Platform.isAndroid ||
      await _platform.invokeMethod<bool>('requestLocalNetwork') == true;
  Future<bool> saveZip(Uint8List bytes) async =>
      await _export.invokeMethod<String>('saveZip', {
        'bytes': bytes,
        'filename': 'cookdex-recipes.zip',
      }) ==
      'saved';
  Future<void> testKey(ImportPlatform platform) async {
    final settings = await platform.settings();
    if (!settings.hasKey) throw StateError('Save a Gemini key first.');
    // Only an explicit Test key button calls this; no recipes/drafts are included.
    final response = await platform.providerRequest(
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'model': settings.model,
            'input': 'Reply OK.',
            'store': false,
            'generation_config': {'max_output_tokens': 32},
          }),
        ),
      ),
    );
    if (response.status < 200 || response.status >= 300) {
      throw StateError(
        'Gemini key test failed (HTTP ${response.status}). Check the key, model and quota.',
      );
    }
  }
}
