import 'dart:convert';
import 'dart:io';
import 'dart:developer' as timeline;

/// Local raw form state only. Callers supply a fresh Flutter-private path.
abstract interface class DraftStorage {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> value);
  Future<void> clear();
}

/// Accept a snapshot already serialized by the editor without decoding and
/// encoding the same large draft again on the UI isolate.
abstract interface class EncodedDraftStorage {
  Future<void> writeEncoded(String value);
}

class MemoryDraftStorage implements DraftStorage {
  Map<String, dynamic>? _value;
  @override
  Future<Map<String, dynamic>?> read() async => _value == null
      ? null
      : jsonDecode(jsonEncode(_value)) as Map<String, dynamic>;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    _value = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  }

  @override
  Future<void> clear() async {
    _value = null;
  }
}

class FileDraftStorage implements DraftStorage, EncodedDraftStorage {
  FileDraftStorage(this.path, {this.limitBytes = maxBytes});
  final String path;
  final int limitBytes;
  Future<void> _queue = Future.value();
  static const maxBytes = 8 * 1024 * 1024;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    // One failed write must not permanently poison future retries/clear.
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  Future<Map<String, dynamic>?> read() => _serialized(() async {
    final file = File(path);
    if (!await file.exists()) return null;
    if (await file.length() > limitBytes) {
      throw const FormatException('Saved draft exceeds its size limit.');
    }
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Saved draft could not be read.');
    }
    return value;
  });

  @override
  Future<void> write(Map<String, dynamic> value) {
    // Freeze immediately so queued writes never observe later field mutations.
    final encoded = timeline.Timeline.timeSync(
      'editor.draft.storageEncode',
      () => jsonEncode(value),
    );
    return writeEncoded(encoded);
  }

  @override
  Future<void> writeEncoded(String value) {
    final bytes = utf8.encode(value);
    if (bytes.length > limitBytes) {
      return Future.error(
        const FormatException('Draft exceeds its size limit.'),
      );
    }
    return _serialized(() async {
      final temporary = File('$path.tmp');
      await temporary.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(path);
    });
  }

  @override
  Future<void> clear() => _serialized(() async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  });
}
