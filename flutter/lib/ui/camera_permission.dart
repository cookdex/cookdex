import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _CameraNotice { denied, blocked, unavailable, settingsUnavailable }

/// Requests Android access at the camera button and keeps the alternative on
/// the same screen when permission is denied.
mixin CameraPermissionFeedback<T extends StatefulWidget> on State<T> {
  static const _platform = MethodChannel('com.sylph.cookdex.dev/platform');
  _CameraNotice? _notice;
  final _noticeKey = GlobalKey();
  bool _asking = false;
  bool _openingSettings = false;

  void clearCameraNotice() {
    if (_notice != null) setState(() => _notice = null);
  }

  void _showCameraNotice(_CameraNotice notice) {
    setState(() => _notice = notice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _noticeKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    });
  }

  Future<void> withCameraAccess(
    Future<void> Function() action, {
    bool needsCamera = true,
  }) async {
    if (!needsCamera || defaultTargetPlatform != TargetPlatform.android) {
      clearCameraNotice();
      await action();
      return;
    }
    if (_asking || _openingSettings) return;
    _asking = true;
    try {
      String? answer;
      try {
        answer = await _platform.invokeMethod<String>(
          'requestCameraPermission',
        );
      } on PlatformException {
        answer = null;
      } on MissingPluginException {
        answer = null;
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
      switch (answer) {
        case 'granted':
          clearCameraNotice();
          await action();
        case 'denied':
          _showCameraNotice(_CameraNotice.denied);
        case 'blocked':
          _showCameraNotice(_CameraNotice.blocked);
        case 'cancelled':
          return;
        default:
          _showCameraNotice(_CameraNotice.unavailable);
      }
    } finally {
      _asking = false;
    }
  }

  Future<void> _openSettings() async {
    if (_openingSettings) return;
    _openingSettings = true;
    try {
      final allowed = await _platform.invokeMethod<bool>('openCameraSettings');
      if (mounted && allowed == true) clearCameraNotice();
    } on PlatformException {
      if (mounted) _showCameraNotice(_CameraNotice.settingsUnavailable);
    } finally {
      _openingSettings = false;
    }
  }

  Widget? cameraPermissionNotice({bool scanning = false}) {
    final notice = _notice;
    if (notice == null) return null;
    final message = switch (notice) {
      _CameraNotice.denied =>
        scanning
            ? 'Tap Scan QR code again to allow camera access, or paste the invitation.'
            : 'To take photos, tap Camera again and allow access, or choose Gallery.',
      _CameraNotice.blocked => 'Camera access is off for cookdex.',
      _CameraNotice.unavailable =>
        scanning
            ? 'Camera access is unavailable. You can paste the invitation.'
            : 'Camera access is unavailable. You can choose Gallery.',
      _CameraNotice.settingsUnavailable =>
        'Could not open settings. Open cookdex in Android app settings.',
    };
    return Padding(
      key: _noticeKey,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(liveRegion: true, child: Text(message)),
          if (notice == _CameraNotice.blocked ||
              notice == _CameraNotice.settingsUnavailable)
            TextButton(
              onPressed: _openSettings,
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
  }
}
