import 'dart:async';
import 'dart:convert';

import 'package:cookdex/import_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'smart_create_photo.dart';

/// Only instantiated by widget tests and the isolated Android replay target.
class CreateReplayPlatform extends Fake implements ImportPlatform {
  CreateReplayPlatform({this.keyPresent = true});

  bool keyPresent;
  int photoCount = 1;
  int requests = 0;
  int status = 200;
  Completer<void>? hold;
  final replies = <Map<String, dynamic>>[];

  @override
  Future<SmartImportSettings> settings() async =>
      SmartImportSettings(hasKey: keyPresent, model: 'gemini-3.5-flash-lite');

  @override
  Future<PhotoSelection> pickPhotos({
    required bool camera,
    required int maxCount,
  }) async => PhotoSelection(
    photos: [
      for (var i = 0; i < photoCount && i < maxCount; i++)
        ImportPhoto(
          id: 'produce-$i',
          jpeg: base64Decode(
            i == 0 ? syntheticProduceJpeg : syntheticVegetablesJpeg,
          ),
        ),
    ],
  );

  @override
  Future<ProviderReply> providerRequest(Uint8List body) async {
    requests++;
    final bytes = status == 200
        ? utf8.encode(
            jsonEncode({
              'steps': [
                {
                  'type': 'model_output',
                  'content': [
                    {'type': 'text', 'text': jsonEncode(replies.removeAt(0))},
                  ],
                },
              ],
            }),
          )
        : utf8.encode('{"error":{"message":"Synthetic service failure"}}');
    await hold?.future;
    return ProviderReply(status: status, bytes: Uint8List.fromList(bytes));
  }

  @override
  Future<void> cancel() async {}
}
