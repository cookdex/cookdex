import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'src/rust/api.dart';
import 'import_page_fetcher.dart';

class SmartImportSettings {
  const SmartImportSettings({required this.hasKey, required this.model});
  final bool hasKey;
  final String model;
}

class ImportPhoto {
  ImportPhoto({required this.id, required this.jpeg, this.originalId});
  final String? originalId;
  final String id;
  final Uint8List jpeg;
  PreparedPhoto toPreparedPhoto() =>
      PreparedPhoto(mimeType: 'image/jpeg', bytes: jpeg);
  Map<String, Object> toJson() => {
    'id': id,
    'jpeg': base64Encode(jpeg),
    'originalId': ?originalId,
  };
  factory ImportPhoto.fromJson(Map<String, dynamic> value) => ImportPhoto(
    id: value['id'] as String,
    originalId: value['originalId'] as String?,
    jpeg: base64Decode(value['jpeg'] as String),
  );
}

class PhotoSelection {
  const PhotoSelection({required this.photos, this.errors = const []});
  final List<ImportPhoto> photos;
  final List<String> errors;
}

class ImportPage {
  const ImportPage({required this.html, required this.url});
  final String html;
  final String url;
}

class ProviderReply {
  const ProviderReply({required this.status, required this.bytes});
  final int status;
  final Uint8List bytes;
}

abstract class ImportPlatform {
  Future<SmartImportSettings> settings();
  Future<void> saveSettings({required String key, required String model});
  Future<void> removeKey();
  Future<String?> pickText();
  Future<PhotoSelection> pickPhotos({
    required bool camera,
    required int maxCount,
  });
  Future<ImportPage> fetchPage(String url);
  Future<ProviderReply> providerRequest(Uint8List body);
  Future<void> cancel();
}

abstract interface class ImportPhotoArchivePlatform {
  Future<bool> canSavePhotos();
  Future<List<int>> savePhotos(List<String> ids, String title);
  Future<void> discardOriginals(List<String> ids);
}

class NativeImportPlatform
    implements ImportPlatform, ImportPhotoArchivePlatform {
  @override
  Future<bool> canSavePhotos() async =>
      Platform.isAndroid &&
      await _channel.invokeMethod<bool>('canSavePhotos') == true;
  @override
  Future<List<int>> savePhotos(List<String> ids, String title) async =>
      (await _channel.invokeListMethod<int>('savePhotos', {
        'ids': ids,
        'title': title,
      }))!;
  @override
  Future<void> discardOriginals(List<String> ids) async {
    if (Platform.isAndroid && ids.isNotEmpty) {
      await _channel.invokeMethod<void>('discardOriginals', {'ids': ids});
    }
  }

  final _pages = ImportPageFetcher();
  static const _channel = MethodChannel('com.sylph.cookdex.dev/import');
  @override
  Future<SmartImportSettings> settings() async {
    final result = (await _channel.invokeMapMethod<String, dynamic>(
      'settings',
    ))!;
    return SmartImportSettings(
      hasKey: result['hasKey'] as bool,
      model: result['model'] as String,
    );
  }

  @override
  Future<void> saveSettings({required String key, required String model}) =>
      _channel.invokeMethod<void>('saveSettings', {'key': key, 'model': model});
  @override
  Future<void> removeKey() => _channel.invokeMethod<void>('removeKey');
  @override
  Future<String?> pickText() async {
    if (Platform.isWindows) {
      final bytes = await const MethodChannel('com.sylph.cookdex.dev/export')
          .invokeMethod<Uint8List>('pickText');
      return bytes == null ? null : utf8.decode(bytes);
    }
    return _channel.invokeMethod<String>('pickText');
  }

  @override
  Future<PhotoSelection> pickPhotos({
    required bool camera,
    required int maxCount,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickPhotos',
      {'camera': camera, 'maxCount': maxCount},
    );
    if (result == null) return const PhotoSelection(photos: []);
    return PhotoSelection(
      photos: (result['photos'] as List)
          .cast<Uint8List>()
          .indexed
          .map(
            (entry) => ImportPhoto(
              id: '${DateTime.now().microsecondsSinceEpoch}-${_nextPhoto++}',
              jpeg: entry.$2,
              originalId:
                  (result['originalIds'] as List?)?[entry.$1] as String?,
            ),
          )
          .toList(),
      errors: (result['errors'] as List).cast<String>(),
    );
  }

  static int _nextPhoto = 0;
  @override
  Future<ImportPage> fetchPage(String url) => _pages.fetch(url);
  @override
  Future<ProviderReply> providerRequest(Uint8List body) async {
    final result = (await _channel.invokeMapMethod<String, dynamic>(
      'providerRequest',
      body,
    ))!;
    return ProviderReply(
      status: result['status'] as int,
      bytes: result['bytes'] as Uint8List,
    );
  }

  @override
  Future<void> cancel() async {
    _pages.cancel();
    await _channel.invokeMethod<void>('cancel');
  }
}
