import 'dart:io';

import 'app_identity.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract class AppPlatform {
  bool get isAndroid;
  Future<String> privateRoot();
  Future<Uint8List?> pickRecipeZip();
  Future<void> setKeepScreenOn(bool enabled);
  Future<void> openSource(String url);
  Future<void> backgroundTask();
  Future<ColorScheme?> wallpaperColorScheme({
    Brightness brightness = Brightness.dark,
  });
}

class NativeAppPlatform implements AppPlatform {
  static const _channel = MethodChannel('com.sylph.cookdex.dev/platform');
  Future<void> verifyIdentity() async {
    final nativeId = await _channel.invokeMethod<String>('applicationId');
    if (nativeId != appId &&
        !(isDevelopment && nativeId == 'com.sylph.cookdex.dev.profile')) {
      throw StateError('Native and Dart application identities do not match.');
    }
  }

  @override
  bool get isAndroid => Platform.isAndroid;
  @override
  Future<String> privateRoot() async {
    if (isAndroid) return (await _channel.invokeMethod<String>('privateRoot'))!;
    if (Platform.isWindows) {
      final root = Platform.environment['LOCALAPPDATA'];
      if (root == null) {
        throw StateError('Private application storage unavailable.');
      }
      return '$root/$appId/flutter-v1';
    }
    throw UnsupportedError('Unsupported platform.');
  }

  @override
  Future<Uint8List?> pickRecipeZip() async {
    if (!isAndroid) {
      return const MethodChannel('com.sylph.cookdex.dev/export')
          .invokeMethod<Uint8List>('pickRecipeZip');
    }
    return _channel.invokeMethod<Uint8List>('pickRecipeZip');
  }

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    if (isAndroid) await _channel.invokeMethod<void>('keepScreenOn', enabled);
  }

  @override
  Future<void> openSource(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException(
        'Only HTTP and HTTPS source links can be opened.',
      );
    }
    if (isAndroid) {
      await _channel.invokeMethod<void>('openSource', url);
    } else if (Platform.isWindows) {
      await Process.run('rundll32.exe', [
        'url.dll,FileProtocolHandler',
        uri.toString(),
      ]);
    }
  }

  @override
  Future<void> backgroundTask() async {
    if (isAndroid) await _channel.invokeMethod<void>('backgroundTask');
  }

  @override
  Future<ColorScheme?> wallpaperColorScheme({
    Brightness brightness = Brightness.dark,
  }) async {
    if (!isAndroid) return null;
    final values = await _channel.invokeMapMethod<String, int>(
      'wallpaperColors',
      brightness.name,
    );
    if (values == null) return null;
    Color role(String name) {
      final value = values[name];
      if (value == null) throw FormatException('Missing system color: $name');
      return Color(value);
    }

    return ColorScheme(
      brightness: brightness,
      primary: role('primary'),
      onPrimary: role('onPrimary'),
      primaryContainer: role('primaryContainer'),
      onPrimaryContainer: role('onPrimaryContainer'),
      primaryFixed: role('primaryFixed'),
      primaryFixedDim: role('primaryFixedDim'),
      onPrimaryFixed: role('onPrimaryFixed'),
      onPrimaryFixedVariant: role('onPrimaryFixedVariant'),
      secondary: role('secondary'),
      onSecondary: role('onSecondary'),
      secondaryContainer: role('secondaryContainer'),
      onSecondaryContainer: role('onSecondaryContainer'),
      secondaryFixed: role('secondaryFixed'),
      secondaryFixedDim: role('secondaryFixedDim'),
      onSecondaryFixed: role('onSecondaryFixed'),
      onSecondaryFixedVariant: role('onSecondaryFixedVariant'),
      tertiary: role('tertiary'),
      onTertiary: role('onTertiary'),
      tertiaryContainer: role('tertiaryContainer'),
      onTertiaryContainer: role('onTertiaryContainer'),
      tertiaryFixed: role('tertiaryFixed'),
      tertiaryFixedDim: role('tertiaryFixedDim'),
      onTertiaryFixed: role('onTertiaryFixed'),
      onTertiaryFixedVariant: role('onTertiaryFixedVariant'),
      error: role('error'),
      onError: role('onError'),
      errorContainer: role('errorContainer'),
      onErrorContainer: role('onErrorContainer'),
      surface: role('surface'),
      onSurface: role('onSurface'),
      surfaceDim: role('surfaceDim'),
      surfaceBright: role('surfaceBright'),
      surfaceContainerLowest: role('surfaceContainerLowest'),
      surfaceContainerLow: role('surfaceContainerLow'),
      surfaceContainer: role('surfaceContainer'),
      surfaceContainerHigh: role('surfaceContainerHigh'),
      surfaceContainerHighest: role('surfaceContainerHighest'),
      onSurfaceVariant: role('onSurfaceVariant'),
      outline: role('outline'),
      outlineVariant: role('outlineVariant'),
      inverseSurface: role('inverseSurface'),
      onInverseSurface: role('onInverseSurface'),
      inversePrimary: role('inversePrimary'),
      surfaceTint: role('surfaceTint'),
      shadow: role('shadow'),
      scrim: role('scrim'),
    );
  }
}
