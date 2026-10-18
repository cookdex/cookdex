import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/bridge_loader.dart';
import 'package:cookdex/src/rust/api.dart';
import 'package:cookdex/ui/pairing_invitation_qr.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zxing/flutter_zxing.dart' as zxing;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real and maximum realistic invitations decode with ZXing C++', (
    tester,
  ) async {
    await initializeBridge();
    final reservation = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final port = reservation.port;
    await reservation.close();
    expect(port, isNot(anyOf(47831, 47832)));
    final root = await Directory.systemTemp.createTemp('cookdex-qr-');
    final session = await CoreSession.openWithSyncPort(
      privateRoot: root.path,
      port: port,
    );
    try {
      await session.syncConfigure(enabled: true, name: 'Synthetic QR test');
      await session.syncHostActive(active: true);
      // An actual core-generated one-use invitation, with fresh ephemeral keys.
      // No peer is paired and no recipe data or external service is accessed.
      final real = await session.syncInvitation(address: '127.0.0.1');
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(real.substring(12)))),
      ) as Map<String, dynamic>;
      // Generated invitations have a 100-byte name, seven alternatives, UUIDs,
      // and a 32-byte key. Use maximum-width synthetic private IPv4 endpoints.
      // Replace host-derived addresses; never persist a machine's actual LAN IP.
      payload['name'] = 'Kitchen tablet '.padRight(100, 'x');
      payload['address'] = '192.168.255.254:47832';
      payload['alternatives'] = List.generate(
        7,
        (i) => '192.168.255.${253 - i}:47832',
      );
      String encode() =>
          'recipe-pair:${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}';
      final longest = encode();
      // JSON escaping can make an accepted name larger than ordinary names.
      payload['name'] = List.filled(100, '"').join();
      final escaped = encode();
      payload['name'] = List.filled(25, '🍳').join();
      final unicode = encode();
      for (final code in [real, longest, escaped, unicode]) {
        expect(code.length, lessThanOrEqualTo(4096));
        // The actual widget uses 288dp at 320dp phone width, capped at 340dp.
        for (final size in [288.0, 340.0]) {
          final key = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: SizedBox.square(
                      dimension: size,
                      child: PairingInvitationQr(invitation: code),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          // Render real pixels with the shipping PrettyQrView, no second encoder.
          final image = await boundary.toImage(pixelRatio: 3);
          try {
            final pixels = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final result = zxing.zx.readBarcode(
              pixels!.buffer.asUint8List(),
              zxing.DecodeParams(
                format: zxing.Format.qrCode,
                imageFormat: zxing.ImageFormat.rgba,
                width: image.width,
                height: image.height,
                tryHarder: true,
              ),
            );
            expect(result.isValid, isTrue, reason: result.error);
            // Avoid printing the generated invitation/secret on assertion failure.
            expect(result.text == code, isTrue);
          } finally {
            image.dispose();
          }
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      await root.delete(recursive: true);
    }
  });
}
