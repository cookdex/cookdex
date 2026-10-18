import 'package:flutter/material.dart';

import 'src/rust/api.dart';
import 'sync_controller.dart';

const syncFailureColor = Color(0xFFFFA6A6);
const syncConflictColor = Color(0xFFE6C66A);
const syncPendingColor = Color(0xFFBBC1C7);
const syncCompleteColor = Color(0xFFA2BBA8);
const syncOffColor = Color(0xFF9EA3AA);

/// Status hues remain recognizable with readable dots/text on either surface.
Color syncColorForBrightness(Color color, Brightness brightness) {
  if (brightness == Brightness.dark) return color;
  return switch (color) {
    syncFailureColor => const Color(0xffa12d32),
    syncConflictColor => const Color(0xff755900),
    syncCompleteColor => const Color(0xff3f654b),
    syncPendingColor => const Color(0xff515e69),
    syncOffColor => const Color(0xff5b626a),
    _ => color,
  };
}

class SyncPresentation {
  const SyncPresentation(this.label, this.color, this.sentence);
  final String label, sentence;
  final Color color;
}

SyncPresentation syncPresentation(SyncController c, int conflictCount) {
  final s = c.status;
  final updateReason = [
    c.error,
    s?.error,
    ...?s?.reports.where((r) => r.status == 'error').map((r) => r.error),
  ].where(_needsUpdate).firstOrNull;
  if (updateReason != null) {
    return SyncPresentation(
      'Update needed',
      syncFailureColor,
      _updateAdvice(updateReason),
    );
  }
  if (c.error != null ||
      s?.error != null ||
      (s?.reports.any((r) => r.status == 'error') ?? false)) {
    return const SyncPresentation(
      'Sync failure',
      syncFailureColor,
      'Sync needs attention. See the reason below.',
    );
  }
  if (conflictCount > 0) {
    return SyncPresentation(
      'Sync conflict',
      syncConflictColor,
      '$conflictCount ${conflictCount == 1 ? 'recipe needs' : 'recipes need'} a choice.',
    );
  }
  if (s == null || !s.enabled || s.peers.isEmpty) {
    return const SyncPresentation('Sync off', syncOffColor, 'Sync is off.');
  }
  if (s.peers.any((peer) => peer.pairingPending)) {
    return const SyncPresentation(
      'Pairing unfinished',
      syncPendingColor,
      'Try Sync now, or create a new invitation.',
    );
  }
  if (!c.receiptsCurrent || s.peers.any((p) => p.caughtUp != true)) {
    if (c.inChangeGrace) {
      return const SyncPresentation(
        'Syncing',
        syncPendingColor,
        'Sharing your latest changes…',
      );
    }
    return const SyncPresentation(
      'Not synced',
      syncPendingColor,
      'Some changes are waiting to reach your devices.',
    );
  }
  final times = s.peers.map((p) => p.lastSync).whereType<int>().toList();
  times.sort();
  final when = times.length == s.peers.length
      ? ' · ${readableSyncTime(times.first)}'
      : '';
  return SyncPresentation(
    'Synced',
    syncCompleteColor,
    'Synced with ${s.peers.length} ${s.peers.length == 1 ? 'device' : 'devices'}$when',
  );
}

String readableSyncTime(int? epochSeconds, {DateTime? now}) {
  if (epochSeconds == null) return 'Not synced yet';
  final at = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000).toLocal();
  final localNow = (now ?? DateTime.now()).toLocal();
  final ago = localNow.difference(at);
  if (!ago.isNegative && ago.inSeconds < 60) return 'just now';
  if (!ago.isNegative && ago.inMinutes < 60) return '${ago.inMinutes} min ago';
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final time =
      '$hour:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
  if (at.year == localNow.year &&
      at.month == localNow.month &&
      at.day == localNow.day) {
    return 'Today $time';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[at.month - 1]} ${at.day}${at.year == localNow.year ? '' : ', ${at.year}'} · $time';
}

String peerSyncText(SyncPeer peer, SyncStatus status) {
  if (peer.pairingPending) {
    return 'Sync now to finish, or try a new invitation. Forget removes this unfinished setup.';
  }
  final r = status.reports.where((r) => r.id == peer.id).firstOrNull;
  if (r?.status == 'error' && _needsUpdate(r?.error)) {
    final advice = _updateAdvice(r!.error!);
    return advice == 'Update all cookdex devices, then retry.'
        ? 'Update needed · update all cookdex devices'
        : 'Update needed · $advice';
  }
  if (r?.status == 'error') return 'Sync failure · needs attention';
  if (r?.status == 'waiting') {
    final seconds = r?.retryAfterSeconds;
    return 'Waiting for device${seconds == null ? '' : ' · retrying in ${(seconds / 60).ceil().clamp(1, 999)} min'}';
  }
  if (peer.caughtUp != true) return 'Waiting for changes to sync';
  return 'Synced ${readableSyncTime(peer.lastSync)}';
}

bool _needsUpdate(String? message) {
  final text = message?.toLowerCase() ?? '';
  return text.contains('incompatible') ||
      text.contains('update all cookdex devices') ||
      text.contains('update cookdex on the other device') ||
      text.contains('this device needs an update') ||
      text.contains('update needed');
}

String _updateAdvice(String message) {
  if (message.contains('Update cookdex on the other device')) {
    return 'Update cookdex on the other device to keep syncing.';
  }
  if (message.contains('This device needs an update')) {
    return 'This device needs an update to keep syncing.';
  }
  return 'Update all cookdex devices, then retry.';
}

Color peerSyncColor(SyncPeer peer, SyncStatus status) {
  if (peer.pairingPending) return syncPendingColor;
  if (status.reports.any((r) => r.id == peer.id && r.status == 'error')) {
    return syncFailureColor;
  }
  return peer.caughtUp == true ? syncCompleteColor : syncPendingColor;
}
