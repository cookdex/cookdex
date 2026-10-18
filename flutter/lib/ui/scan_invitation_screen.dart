import 'package:flutter/material.dart';
import 'package:camera/camera.dart' show availableCameras;
import 'package:flutter_zxing/flutter_zxing.dart';

/// Camera frames are decoded locally; only the accepted invitation leaves here.
class ScanInvitationScreen extends StatefulWidget {
  const ScanInvitationScreen({super.key});

  @override
  State<ScanInvitationScreen> createState() => _ScanInvitationScreenState();
}

class _ScanInvitationScreenState extends State<ScanInvitationScreen> {
  bool _accepted = false;
  bool _cameraUnavailable = false;
  bool _checkingCamera = true;
  CameraController? _cameraController;

  void _cameraChanged() {
    if (mounted &&
        !_accepted &&
        !_cameraUnavailable &&
        (_cameraController?.value.hasError ?? false)) {
      setState(() => _cameraUnavailable = true);
    }
  }

  @override
  void dispose() {
    _cameraController?.removeListener(_cameraChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkCamera();
  }

  Future<void> _checkCamera() async {
    // ReaderWidget leaves an empty camera list on its loading view indefinitely.
    // Give camera-less devices the same usable paste fallback as permission errors.
    var available = false;
    try {
      available = (await availableCameras()).isNotEmpty;
    } catch (_) {
      // The friendly fallback covers missing hardware and platform failures.
    }
    if (!mounted) return;
    setState(() {
      _cameraUnavailable = !available;
      _checkingCamera = false;
    });
  }

  void _onScan(Code result) {
    if (!mounted || _accepted || _cameraUnavailable || !result.isValid) return;
    final code = result.text;
    if (code == null ||
        !code.startsWith('recipe-pair:') ||
        code.length > 4096) {
      return;
    }
    _accepted = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan invitation')),
    body: SafeArea(
      top: false,
      child: _cameraUnavailable
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Camera access is unavailable. Allow Camera in Android app settings, or go back and paste the invitation.',
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to pairing'),
                    ),
                  ],
                ),
              ),
            )
          : _checkingCamera
          ? const Center(child: CircularProgressIndicator())
          : ReaderWidget(
              codeFormat: Format.qrCode,
              // Preserve the full-camera scan area; dense invitations need pixels.
              cropPercent: 0,
              resolution: ResolutionPreset.veryHigh,
              tryHarder: true,
              tryInverted: true,
              scanDelay: const Duration(milliseconds: 250),
              scanDelaySuccess: const Duration(milliseconds: 250),
              showScannerOverlay: false,
              showFlashlight: false,
              showToggleCamera: false,
              showGallery: false,
              onScan: _onScan,
              onControllerCreated: (controller, error) {
                if (!mounted || _accepted || _cameraUnavailable) return;
                _cameraController?.removeListener(_cameraChanged);
                _cameraController = controller;
                controller?.addListener(_cameraChanged);
                if (error != null) {
                  setState(() => _cameraUnavailable = true);
                } else {
                  _cameraChanged();
                }
              },
            ),
    ),
  );
}
