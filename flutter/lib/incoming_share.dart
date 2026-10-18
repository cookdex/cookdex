import 'dart:async';

import 'package:flutter/services.dart';

import 'import_controller.dart';
import 'import_service.dart';

class IncomingShare {
  const IncomingShare(this.value);
  final Map<String, dynamic> value;
  bool get coldStart => value['coldStart'] == true;
  Future<void> apply(ImportController c) async {
    if (value['error'] case final String message) {
      c.error = message;
      c.changed(clearError: false);
      return;
    }
    if (value['photos'] case final List photos) {
      c.tab = ImportTab.photos;
      c.photos.addAll(
        photos.cast<Uint8List>().indexed.map(
          (entry) => ImportPhoto(
            id: 'shared-${DateTime.now().microsecondsSinceEpoch}-${entry.$1}',
            jpeg: entry.$2,
            originalId: (value['originalIds'] as List?)?[entry.$1] as String?,
          ),
        ),
      );
      c.warnings.addAll((value['errors'] as List? ?? []).cast<String>());
    } else {
      final text = value['text'] as String? ?? '';
      final trimmed = text.trim();
      final uri = Uri.tryParse(trimmed);
      final link =
          !trimmed.contains(RegExp(r'\s')) &&
          uri != null &&
          ['http', 'https'].contains(uri.scheme) &&
          uri.host.isNotEmpty;
      c.tab = link ? ImportTab.link : ImportTab.text;
      if (link) {
        c.link = trimmed;
      } else {
        c.text = text;
      }
    }
    c.changed();
  }
}

/// Native retains a bounded queue until Flutter is listening; Flutter retains
/// each prepared payload until the current editor/overlay has safely closed.
class IncomingShares {
  IncomingShares({required this.onReady});
  final void Function() onReady;
  static const channel = MethodChannel('com.sylph.cookdex.dev/incoming');
  final List<IncomingShare> _pending = [];
  bool _disposed = false, _reading = false, _readAgain = false;
  void start() {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'ready') await _read();
    });
    unawaited(_read());
  }

  Future<void> _read() async {
    if (_disposed) return;
    if (_reading) {
      _readAgain = true;
      return;
    }
    _readAgain = false;
    _reading = true;
    try {
      while (_pending.length < 4 && !_disposed) {
        final value = await channel.invokeMapMethod<String, dynamic>('take');
        if (value == null || _disposed) break;
        _pending.add(IncomingShare(value));
      }
    } on MissingPluginException {
      /* Host widget tests and Windows have no intake. */
    } on PlatformException {
      /* A rejected payload is surfaced natively. */
    } finally {
      _reading = false;
      if (!_disposed) {
        if (_readAgain && _pending.length < 4) {
          unawaited(_read());
        } else {
          onReady();
        }
      }
    }
  }

  IncomingShare? take() {
    if (_pending.isEmpty) return null;
    final value = _pending.removeAt(0);
    unawaited(_read());
    return value;
  }

  bool get hasPending => _pending.isNotEmpty;
  Future<bool> finishIfEmpty() async {
    if (_pending.isNotEmpty || _reading) return false;
    return await channel.invokeMethod<bool>('finishIfEmpty') == true;
  }

  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
    _pending.clear();
  }
}
