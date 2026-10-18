import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

/// Shared by the pairing screen and the native decoder round-trip test.
class PairingInvitationQr extends StatelessWidget {
  const PairingInvitationQr({super.key, required this.invitation});

  final String invitation;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'One-use cookdex pairing invitation QR code',
    child: ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: PrettyQrView.data(
          data: invitation,
          decoration: const PrettyQrDecoration(
            shape: PrettyQrSquaresSymbol(color: Colors.black),
            quietZone: PrettyQrQuietZone.standard,
          ),
        ),
      ),
    ),
  );
}
