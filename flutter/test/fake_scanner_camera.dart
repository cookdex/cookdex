import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';

/// Host-only camera substitute: no image frames, native texture or device access.
/// The visible label identifies screenshots as synthetic preview data.
class FakeScannerCamera extends CameraPlatform {
  bool unavailable = false;
  bool noCameras = false;
  int disposals = 0;
  int streamStarts = 0;
  int streamStops = 0;
  final _errors = StreamController<CameraErrorEvent>.broadcast();

  void failCamera() =>
      _errors.add(CameraErrorEvent(1, 'Synthetic camera disconnected'));

  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (unavailable) throw CameraException('CameraAccessDenied', 'Fixture');
    if (noCameras) return [];
    return const [
      CameraDescription(
        name: 'fixture',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 90,
      ),
    ];
  }

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async => 1;
  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  bool supportsImageStreaming() => true;
  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => StreamController<CameraImageData>(
    onListen: () => streamStarts++,
    onCancel: () {
      streamStops++;
    },
  ).stream;
  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 1;
  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;
  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}
  @override
  Future<void> dispose(int cameraId) async {
    disposals++;
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(
    key: Key('synthetic-camera-preview'),
    color: Color(0xff30383d),
    child: Center(
      child: Text(
        'Synthetic camera preview',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white),
      ),
    ),
  );
}
