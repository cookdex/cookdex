import 'dart:async';

import 'package:flutter/foundation.dart';

import 'recipe_store.dart';
import 'app_identity.dart';
import 'src/rust/api.dart';

abstract class SyncBackend {
  Future<SyncStatus> status();
  Future<void> hostActive(bool active);
  Future<void> configure(bool enabled, String name);
  Future<void> pairing(bool active);
  Future<void> dismissPairingNotice() async {}
  Future<String> invitation(String address);
  Future<void> pair(String code);
  Future<void> forget(String id);
  Future<void> sync();
  Future<void> resolve(Conflict conflict, ConflictChoice choice);
}

class RustSyncBackend implements SyncBackend {
  RustSyncBackend(this.session);
  final CoreSession session;
  @override
  Future<SyncStatus> status() => session.syncStatus();
  @override
  Future<void> hostActive(bool active) =>
      session.syncHostActive(active: active);
  @override
  Future<void> configure(bool enabled, String name) =>
      session.syncConfigure(enabled: enabled, name: name);
  @override
  Future<void> pairing(bool active) => session.syncPairing(pairing: active);
  @override
  Future<void> dismissPairingNotice() => session.syncDismissPairingNotice();
  @override
  Future<String> invitation(String address) =>
      session.syncInvitation(address: address);
  @override
  Future<void> pair(String code) => session.syncPair(code: code);
  @override
  Future<void> forget(String id) => session.syncForget(id: id);
  @override
  Future<void> sync() => session.syncNow();
  @override
  Future<void> resolve(Conflict conflict, ConflictChoice choice) async {
    await session.resolveConflict(
      id: conflict.recipeId,
      heads: conflict.versions.map((v) => v.id).toList(),
      choice: choice,
    );
  }
}

/// UI status only. All scheduling, trust and exchanges live in Rust.
class SyncController extends ChangeNotifier {
  SyncController({
    required this.backend,
    required this.refreshRecipes,
    required this.isAndroid,
    required this.requestPermission,
    this.checkPermission,
    this.currentGeneration,
  });
  final SyncBackend backend;
  final int Function()? currentGeneration;
  VoidCallback? detachStore;
  Timer? _graceTimer;
  bool inChangeGrace = false;
  bool get receiptsCurrent =>
      currentGeneration != null &&
      status?.generation != null &&
      status!.generation == currentGeneration!();
  void collectionChanged() {
    if (_closed) return;
    inChangeGrace = true;
    _graceTimer?.cancel();
    _graceTimer = Timer(const Duration(seconds: 5), () {
      inChangeGrace = false;
      _notify();
    });
    _notify();
    unawaited(refresh());
  }

  final Future<void> Function() refreshRecipes;
  final Future<bool> Function() requestPermission;
  final Future<bool> Function()? checkPermission;
  static const permissionMessage =
      'Allow Nearby devices (local network) for $appName to sync. '
      'Tap Sync now or Pair to request access. If denied, allow it in Android app settings.';
  final bool isAndroid;
  SyncStatus? status;
  String? error;
  String? _refreshError;
  bool busy = false;
  bool _closed = false;
  bool _hostActive = false;
  bool _polling = false;
  bool _permissionAllowed = true;
  Timer? _poll;
  Completer<void>? _resume;
  Future<void> _lifecycle = Future.value();
  String get summary =>
      error ??
      (busy
          ? 'Syncing…'
          : status?.enabled != true
          ? 'Off'
          : status?.active != true
          ? 'Paused'
          : status!.peers.any((peer) => peer.pairingPending)
          ? 'Pairing unfinished'
          : status!.peers.isEmpty
          ? 'No paired devices'
          : '${status!.peers.length} paired ${status!.peers.length == 1 ? 'device' : 'devices'}');
  Future<void> lifecycle(bool resumed) {
    _hostActive = !isAndroid || resumed;
    if (_hostActive) {
      _resume?.complete();
      _resume = null;
    }
    _poll?.cancel();
    if (_hostActive) {
      _poll = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(refresh()),
      );
    }
    return _queueAvailability();
  }

  Future<void> _queueAvailability({bool propagateFailure = false}) {
    final update = _lifecycle.then((_) async {
      if (_closed) return;
      try {
        final allowed =
            !isAndroid || (await checkPermission?.call() ?? _permissionAllowed);
        _permissionAllowed = allowed;
        if (_closed) return;
        await backend.hostActive(_hostActive && allowed);
        await refresh();
        if (!allowed && status?.enabled == true) {
          error = permissionMessage;
        } else if (error == permissionMessage) {
          error = null;
        }
        _notify();
      } catch (e) {
        error = message(e);
        _notify();
        if (propagateFailure) rethrow;
      }
    });
    // One failed user action must not poison later lifecycle transitions.
    _lifecycle = update.catchError((Object _) {});
    return update;
  }

  Future<void> refresh() async {
    if (_closed || _polling) return;
    _polling = true;
    try {
      status = await backend.status();
      if (currentGeneration == null ||
          status?.generation != currentGeneration!()) {
        await refreshRecipes();
      }
      if (error == _refreshError) error = null;
      _refreshError = null;
    } catch (e) {
      error = _refreshError = message(e);
    } finally {
      _polling = false;
      _notify();
    }
  }

  Future<T?> run<T>(Future<T> Function() action) async {
    if (busy || _closed) return null;
    busy = true;
    error = null;
    _notify();
    try {
      final value = await action();
      await refresh();
      return value;
    } catch (e) {
      error = message(e);
      await refresh();
      return null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> configure(bool enabled, String name) async {
    await run(() async {
      if (enabled) await ensurePermission();
      await backend.configure(enabled, name);
    });
  }

  /// User-initiated actions also recheck permission after an update/revocation,
  /// even when the saved sync-enabled preference is already true.
  Future<void> ensurePermission() async {
    _permissionAllowed = await requestPermission();
    // Android delivers the permission result before the activity's resume.
    // Wait for that actual lifecycle event; never force a background host on.
    if (_permissionAllowed && isAndroid && !_hostActive && !_closed) {
      await (_resume ??= Completer<void>()).future.timeout(
        const Duration(seconds: 5),
        onTimeout: () =>
            throw StateError('Sync paused. Return to the app and retry.'),
      );
    }
    await _queueAvailability(propagateFailure: true);
    if (_closed) throw StateError('Sync screen closed.');
    if (!_permissionAllowed) throw StateError(permissionMessage);
    if (isAndroid && !_hostActive) {
      throw StateError('Sync paused. Return to the app and retry.');
    }
    if (error == permissionMessage) error = null;
  }

  Future<void> manual() async {
    await run(() async {
      await ensurePermission();
      await backend.sync();
    });
  }

  Future<void> pairing(bool active) => backend.pairing(active);
  Future<void> dismissPairingNotice() async {
    await run(backend.dismissPairingNotice);
  }

  Future<void> forget(String id) async {
    await run(() => backend.forget(id));
  }

  Future<void> resolve(Conflict conflict, ConflictChoice choice) async {
    await run(() => backend.resolve(conflict, choice));
  }

  static String message(Object e) => e is ServiceError
      ? e.message
      : e is StateError
      ? e.message
      : 'Sync could not complete. Check the local network and try again.';
  void _notify() {
    if (!_closed) notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    detachStore?.call();
    _graceTimer?.cancel();
    _poll?.cancel();
    _resume?.complete();
    _resume = null;
    super.dispose();
  }
}

SyncController? syncForStore(
  RecipeStore store,
  bool isAndroid,
  Future<bool> Function() permission,
  Future<bool> Function() checkPermission,
) {
  final repository = store.repository;
  if (repository is! RustRecipeRepository) return null;
  final controller = SyncController(
    backend: RustSyncBackend(repository.session),
    refreshRecipes: store.refresh,
    isAndroid: isAndroid,
    requestPermission: permission,
    checkPermission: checkPermission,
    currentGeneration: () => store.syncGeneration,
  );
  var generation = store.syncGeneration;
  void changed() {
    if (generation == store.syncGeneration) return;
    generation = store.syncGeneration;
    controller.collectionChanged();
  }

  store.addListener(changed);
  controller.detachStore = () => store.removeListener(changed);
  return controller;
}
