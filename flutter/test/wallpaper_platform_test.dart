import 'package:cookdex/app_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Android extends NativeAppPlatform {
  @override
  bool get isAndroid => true;
}

class _Desktop extends NativeAppPlatform {
  @override
  bool get isAndroid => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.sylph.cookdex.dev/platform');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  // Deliberately distinct roles: deriving a new scheme from a single accent
  // cannot reproduce the OS's independently selected secondary/neutral colors.
  final values = <String, int>{
    'primary': 0xff214536,
    'onPrimary': 0xff224737,
    'primaryContainer': 0xff234938,
    'onPrimaryContainer': 0xff244b39,
    'primaryFixed': 0xff254d3a,
    'primaryFixedDim': 0xff264f3b,
    'onPrimaryFixed': 0xff27513c,
    'onPrimaryFixedVariant': 0xff28533d,
    'secondary': 0xff29553e,
    'onSecondary': 0xff2a573f,
    'secondaryContainer': 0xff2b5940,
    'onSecondaryContainer': 0xff2c5b41,
    'secondaryFixed': 0xff2d5d42,
    'secondaryFixedDim': 0xff2e5f43,
    'onSecondaryFixed': 0xff2f6144,
    'onSecondaryFixedVariant': 0xff306345,
    'tertiary': 0xff316546,
    'onTertiary': 0xff326747,
    'tertiaryContainer': 0xff336948,
    'onTertiaryContainer': 0xff346b49,
    'tertiaryFixed': 0xff356d4a,
    'tertiaryFixedDim': 0xff366f4b,
    'onTertiaryFixed': 0xff37714c,
    'onTertiaryFixedVariant': 0xff38734d,
    'error': 0xff39754e,
    'onError': 0xff3a774f,
    'errorContainer': 0xff3b7950,
    'onErrorContainer': 0xff3c7b51,
    'surface': 0xff3d7d52,
    'onSurface': 0xff3e7f53,
    'surfaceDim': 0xff3f8154,
    'surfaceBright': 0xff408355,
    'surfaceContainerLowest': 0xff418556,
    'surfaceContainerLow': 0xff428757,
    'surfaceContainer': 0xff438958,
    'surfaceContainerHigh': 0xff448b59,
    'surfaceContainerHighest': 0xff458d5a,
    'onSurfaceVariant': 0xff468f5b,
    'outline': 0xff47915c,
    'outlineVariant': 0xff48935d,
    'inverseSurface': 0xff49955e,
    'onInverseSurface': 0xff4a975f,
    'inversePrimary': 0xff4b9960,
    'surfaceTint': 0xff4c9b61,
    'shadow': 0xff4d9d62,
    'scrim': 0xff4e9f63,
  };
  for (final brightness in Brightness.values) {
    test('native ${brightness.name} roles are preserved exactly', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'wallpaperColors');
        expect(call.arguments, brightness.name);
        return values;
      });
      final scheme = (await _Android().wallpaperColorScheme(
        brightness: brightness,
      ))!;
      expect(scheme.brightness, brightness);
      final actual = <String, Color>{
        'primary': scheme.primary,
        'onPrimary': scheme.onPrimary,
        'primaryContainer': scheme.primaryContainer,
        'onPrimaryContainer': scheme.onPrimaryContainer,
        'primaryFixed': scheme.primaryFixed,
        'primaryFixedDim': scheme.primaryFixedDim,
        'onPrimaryFixed': scheme.onPrimaryFixed,
        'onPrimaryFixedVariant': scheme.onPrimaryFixedVariant,
        'secondary': scheme.secondary,
        'onSecondary': scheme.onSecondary,
        'secondaryContainer': scheme.secondaryContainer,
        'onSecondaryContainer': scheme.onSecondaryContainer,
        'secondaryFixed': scheme.secondaryFixed,
        'secondaryFixedDim': scheme.secondaryFixedDim,
        'onSecondaryFixed': scheme.onSecondaryFixed,
        'onSecondaryFixedVariant': scheme.onSecondaryFixedVariant,
        'tertiary': scheme.tertiary,
        'onTertiary': scheme.onTertiary,
        'tertiaryContainer': scheme.tertiaryContainer,
        'onTertiaryContainer': scheme.onTertiaryContainer,
        'tertiaryFixed': scheme.tertiaryFixed,
        'tertiaryFixedDim': scheme.tertiaryFixedDim,
        'onTertiaryFixed': scheme.onTertiaryFixed,
        'onTertiaryFixedVariant': scheme.onTertiaryFixedVariant,
        'error': scheme.error,
        'onError': scheme.onError,
        'errorContainer': scheme.errorContainer,
        'onErrorContainer': scheme.onErrorContainer,
        'surface': scheme.surface,
        'onSurface': scheme.onSurface,
        'surfaceDim': scheme.surfaceDim,
        'surfaceBright': scheme.surfaceBright,
        'surfaceContainerLowest': scheme.surfaceContainerLowest,
        'surfaceContainerLow': scheme.surfaceContainerLow,
        'surfaceContainer': scheme.surfaceContainer,
        'surfaceContainerHigh': scheme.surfaceContainerHigh,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
        'onSurfaceVariant': scheme.onSurfaceVariant,
        'outline': scheme.outline,
        'outlineVariant': scheme.outlineVariant,
        'inverseSurface': scheme.inverseSurface,
        'onInverseSurface': scheme.onInverseSurface,
        'inversePrimary': scheme.inversePrimary,
        'surfaceTint': scheme.surfaceTint,
        'shadow': scheme.shadow,
        'scrim': scheme.scrim,
      };
      expect(
        actual.map((name, color) => MapEntry(name, color.toARGB32())),
        values,
      );
    });
  }

  test('unsupported Android preserves unavailable result', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await _Android().wallpaperColorScheme(), isNull);
  });
  test('missing native role fails rather than inventing a palette', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {...values}..remove('secondary'),
    );
    await expectLater(_Android().wallpaperColorScheme(), throwsFormatException);
  });
  test('desktop never requests Android resources', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('Unexpected Android palette request');
    });
    expect(await _Desktop().wallpaperColorScheme(), isNull);
  });
}
