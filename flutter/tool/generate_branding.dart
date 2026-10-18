// Host-only asset renderer. Run from flutter/ with:
// flutter test tool/generate_branding.dart
// Reuses the header's exact outlined skillet glyph; never opens app storage.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:cookdex/ui/theme.dart';

void label(
  Canvas canvas,
  String text,
  double size,
  Offset center, {
  bool icon = false,
  Color? color,
}) {
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: icon ? 'BrandPan' : 'BrandWordmark',
        fontSize: size,
        fontWeight: icon ? FontWeight.w400 : FontWeight.w800,
        color: color ?? cookdexColors.onSurface,
        height: 1,
      ),
    ),
  )..layout();
  painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  painter.dispose();
}

Future<Uint8List> render(int pixels, {bool splash = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixels / (splash ? 288 : 192));
  if (!splash) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 192, 192),
        const Radius.circular(42),
      ),
      Paint()..color = cookdexColors.surface,
    );
  }
  label(
    canvas,
    String.fromCharCode(Symbols.skillet.codePoint),
    splash ? 100 : 128,
    splash ? const Offset(144, 115) : const Offset(96, 96),
    icon: true,
    color: cookdexColors.primary,
  );
  if (splash) {
    label(canvas, 'cookdex', 28, const Offset(144, 186));
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(pixels, pixels);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

Future<void> save(String path, Uint8List bytes) async {
  await File(path).parent.create(recursive: true);
  await File(path).writeAsBytes(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render native pan icon and splash assets', () async {
    final cache = Platform.environment['PUB_CACHE']!;
    final sdk = Platform.environment['FLUTTER_SDK']!;
    for (final entry in {
      'BrandPan':
          '$cache/hosted/pub.dev/material_symbols_icons-4.2960.0/lib/fonts/MaterialSymbolsOutlined.ttf',
      'BrandWordmark':
          '$sdk/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(File(entry.value).readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
    const res = 'android/app/src/main/res';
    for (final entry in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      await save(
        '$res/mipmap-${entry.key}/ic_launcher_production.png',
        await render(entry.value),
      );
    }
    await save(
      '$res/drawable-xxxhdpi/cookdex_splash.png',
      await render(1152, splash: true),
    );
    final sizes = [16, 24, 32, 48, 64, 128, 256];
    final images = <Uint8List>[];
    for (final size in sizes) {
      images.add(await render(size));
    }
    final header = ByteData(6 + 16 * sizes.length)
      ..setUint16(2, 1, Endian.little)
      ..setUint16(4, sizes.length, Endian.little);
    var offset = header.lengthInBytes;
    for (var i = 0; i < sizes.length; i++) {
      final pos = 6 + 16 * i;
      header.setUint8(pos, sizes[i] % 256);
      header.setUint8(pos + 1, sizes[i] % 256);
      header.setUint16(pos + 4, 1, Endian.little);
      header.setUint16(pos + 6, 32, Endian.little);
      header.setUint32(pos + 8, images[i].length, Endian.little);
      header.setUint32(pos + 12, offset, Endian.little);
      offset += images[i].length;
    }
    final ico = BytesBuilder()..add(header.buffer.asUint8List());
    for (final image in images) {
      ico.add(image);
    }
    await save('windows/runner/resources/production_icon.ico', ico.toBytes());
    await save('../artifacts/branding/icon.png', await render(768));
    await save(
      '../artifacts/branding/splash-mark.png',
      await render(864, splash: true),
    );
  });
}
