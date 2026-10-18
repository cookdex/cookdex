import 'dart:convert';
import 'dart:typed_data';

import 'app_platform.dart';
import 'draft_storage.dart';

/// Only the last AI import, stored in Flutter's private local directory.
/// Provider credentials never enter this class. Images/source input are omitted.
class ImportDiagnosticsStore {
  ImportDiagnosticsStore(this._storage);
  DraftStorage? _storage;

  Future<DraftStorage> _resolve() async {
    if (_storage != null) return _storage!;
    final root = await NativeAppPlatform().privateRoot();
    return _storage ??= FileDraftStorage(
      '$root/last-ai-import.json',
      limitBytes: 16 * 1024 * 1024,
    );
  }

  Future<void> write(Map<String, dynamic> value) async {
    await (await _resolve()).write(value);
  }

  Future<String?> read() async {
    final value = await (await _resolve()).read();
    if (value == null) return null;
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  Future<void> clear() async => (await _resolve()).clear();
}

class AiImportDiagnostic {
  AiImportDiagnostic({required String mode, required String model})
    : value = {
        'version': 1,
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'mode': redactImportDiagnostic(mode),
        'model': redactImportDiagnostic(model),
        'attempts': <Map<String, dynamic>>[],
        'validation': 'Preparing request',
      };

  final Map<String, dynamic> value;
  final List<Map<String, dynamic>> _attempts = [];

  void request(Uint8List bytes) {
    var instructions = 'Request instructions unavailable';
    try {
      final request = jsonDecode(utf8.decode(bytes));
      if (request is Map && request['system_instruction'] is String) {
        instructions = request['system_instruction'] as String;
      }
    } catch (_) {
      // Diagnostics do not affect request validation or transport.
    }
    _attempts.add({
      'attempt': _attempts.length + 1,
      'instructions': redactImportDiagnostic(instructions),
      'validation': 'Waiting for reply',
    });
    value['attempts'] = _attempts;
  }

  void reply(int status, Uint8List bytes) {
    _attempts.last['httpStatus'] = status;
    _attempts.last['reply'] = redactImportDiagnostic(
      utf8.decode(bytes, allowMalformed: true),
      limit: 2 * 1024 * 1024,
    );
  }

  void validation(String result) {
    final safe = redactImportDiagnostic(result);
    value['validation'] = safe;
    if (_attempts.isNotEmpty) _attempts.last['validation'] = safe;
  }
}

String redactImportDiagnostic(String text, {int limit = 512 * 1024}) {
  final redacted = text.replaceAll(
    RegExp(r'AIza[A-Za-z0-9_-]+'),
    '[redacted key]',
  );
  // Bound each field so a malformed/oversized reply cannot exhaust storage.
  if (redacted.length <= limit) return redacted;
  return '${String.fromCharCodes(redacted.runes.take(limit))}\n[truncated]';
}
