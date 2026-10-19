import 'pixel_scroll.dart';
import 'retained_screen.dart';
import 'navigation_feedback.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'scan_invitation_screen.dart';
import 'pairing_invitation_qr.dart';

import '../sync_controller.dart';
import 'feedback.dart';

enum PairingPath { invite, join }

class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    required this.controller,
    this.invitationAge,
  });
  final SyncController controller;
  final Duration Function()? invitationAge;
  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _code = TextEditingController();
  final _elapsed = Stopwatch();
  Timer? _tick;
  PairingPath? _path;
  String? _invitation, _invitationId, _address, _invitationError;
  bool _creating = false, _paste = false;
  bool _invitationEnded = false;
  Widget? _qr;
  int get _remaining =>
      (600 - (widget.invitationAge?.call() ?? _elapsed.elapsed).inSeconds)
          .clamp(0, 600);
  bool get _valid =>
      _invitation != null &&
      _remaining > 0 &&
      _invitationId != null &&
      _invitationId == widget.controller.status?.invitationId;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_statusChanged);
  }

  @override
  void didUpdateWidget(covariant PairingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_statusChanged);
      widget.controller.addListener(_statusChanged);
      _statusChanged();
    }
  }

  void _clearInvitation() {
    _tick?.cancel();
    _elapsed.stop();
    _invitation = null;
    _invitationId = null;
    _qr = null;
    _code.clear();
  }

  void _statusChanged() {
    if (!mounted || _invitation == null || _valid) return;
    setState(() {
      _clearInvitation();
      _invitationEnded = true;
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_statusChanged);
    _clearInvitation();
    _code.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final c = widget.controller;
    setState(() {
      _creating = true;
      _clearInvitation();
      _invitationEnded = false;
      _invitationError = null;
    });
    try {
      await c.ensurePermission();
      final addresses = c.status?.addresses ?? [];
      if (addresses.isEmpty) {
        throw StateError('Connect to Wi-Fi, then try again.');
      }
      _elapsed
        ..reset()
        ..start();
      final result = await c.backend.invitation(
        addresses.contains(_address) ? _address! : addresses.first,
      );
      final status = await c.backend.status();
      c.status = status;
      if (!mounted) return;
      setState(() {
        _invitation = result;
        _invitationId = status.invitationId;
        _qr = PairingInvitationQr(invitation: result);
      });
      _statusChanged();
      if (_invitation == null) return;
      _tick?.cancel();
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        _statusChanged();
        if (mounted && _invitation != null) setState(() {});
      });
    } catch (e) {
      if (mounted) setState(() => _invitationError = SyncController.message(e));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _pair(String code) async {
    final c = widget.controller;
    final success = await c.run(() async {
      await c.ensurePermission();
      await c.backend.pair(code.trim());
      return true;
    });
    if (success == true && mounted) {
      _clearInvitation();
      Navigator.pop(context);
    } else if (mounted) {
      final error = c.error?.toLowerCase() ?? '';
      if (error.contains('expired') ||
          error.contains('already used') ||
          error.contains('revoked') ||
          error.contains('create a new invitation')) {
        _code.clear();
      }
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      cookdexRoute(context, builder: (_) => const ScanInvitationScreen()),
    );
    if (code != null && mounted) {
      _code.text = code;
      await _pair(code);
    }
  }

  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: widget.controller,
    builder: (context) {
      final c = widget.controller;
      final addresses = c.status?.addresses ?? [];
      return Scaffold(
        appBar: AppBar(
          title: Text(switch (_path) {
            PairingPath.invite => 'Invite a device',
            PairingPath.join => 'Join a device',
            null => 'Add a device',
          }),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => PixelListView(
              padding: EdgeInsets.symmetric(
                horizontal: constraints.maxWidth > 672
                    ? (constraints.maxWidth - 640) / 2
                    : 16,
                vertical: 16,
              ),
              children: [
                if (_path == null) ...[
                  const Text(
                    'Pair only devices that should share the same recipe book. Edits and deletions will reach every paired device.',
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: const Icon(Symbols.qr_code),
                      title: const Text('Invite a device'),
                      subtitle: const Text(
                        'Show a code for your other device.',
                      ),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => setState(() => _path = PairingPath.invite),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Symbols.add_link),
                      title: const Text('Join a device'),
                      subtitle: Text(
                        c.isAndroid
                            ? 'Scan or paste an invitation.'
                            : 'Paste an invitation.',
                      ),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () => setState(() => _path = PairingPath.join),
                    ),
                  ),
                ] else ...[
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () => setState(() => _path = null),
                    child: const Text('Choose another way'),
                  ),
                  const Text(
                    '1. On the other device, open Settings > Sync > Add a device.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _path == PairingPath.invite
                        ? '2. Choose Join a device. Scan this code or paste the invitation.'
                        : '2. Choose Invite a device. Scan its code or paste the invitation here.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '3. Keep both devices on the same Wi-Fi until pairing finishes.',
                  ),
                  const SizedBox(height: 24),
                  if (_path == PairingPath.invite) ...[
                    const Text(
                      'Each invitation works once and expires after ten minutes.',
                    ),
                    const SizedBox(height: 12),
                    if (_valid) ...[
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 340),
                          child: AspectRatio(aspectRatio: 1, child: _qr),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Expires in ${_remaining ~/ 60}:${(_remaining % 60).toString().padLeft(2, '0')}',
                        textAlign: TextAlign.center,
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton.icon(
                          onPressed: () async {
                            if (!_valid) return;
                            await Clipboard.setData(
                              ClipboardData(text: _invitation!),
                            );
                            if (context.mounted) {
                              showFeedback(context, 'Invitation copied');
                            }
                          },
                          icon: const Icon(Symbols.content_copy),
                          label: const Text('Copy invitation'),
                        ),
                      ),
                    ] else if (_invitationEnded)
                      const Text('Invitation expired, used or revoked.'),
                    Align(
                      alignment: Alignment.center,
                      child: FilledButton(
                        onPressed: _creating || c.busy ? null : _invite,
                        child: const Text('New invitation'),
                      ),
                    ),
                    if (addresses.length > 1)
                      ExpansionTile(
                        title: const Text('Technical details'),
                        children: [
                          const ListTile(
                            subtitle: Text(
                              'Choose a Wi-Fi address if the other device cannot connect.',
                            ),
                          ),
                          for (final address in addresses)
                            ListTile(
                              title: Text(address),
                              trailing: (_address ?? addresses.first) == address
                                  ? const Icon(Symbols.check)
                                  : null,
                              onTap: _creating
                                  ? null
                                  : () => setState(() => _address = address),
                            ),
                        ],
                      ),
                  ] else ...[
                    if (c.isAndroid)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: c.busy ? null : _scan,
                          icon: const Icon(Symbols.qr_code_scanner),
                          label: const Text('Scan QR code'),
                        ),
                      ),
                    if (c.isAndroid && !_paste)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() => _paste = true),
                          child: const Text('Paste invitation'),
                        ),
                      ),
                    if (!c.isAndroid || _paste) ...[
                      if (c.isAndroid) const SizedBox(height: 16),
                      PixelScrollScope(
                        axis: Axis.horizontal,
                        builder: (context) => TextField(
                          scrollController: PrimaryScrollController.of(context),
                          controller: _code,
                          maxLength: 4096,
                          minLines: 2,
                          maxLines: 5,
                          decoration: const InputDecoration(
                            labelText: 'Paste invitation',
                            counterText: '',
                          ),
                          autocorrect: false,
                          enableSuggestions: false,
                          enableIMEPersonalizedLearning: false,
                          textCapitalization: TextCapitalization.none,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: c.busy ? null : () => _pair(_code.text),
                          child: const Text('Pair'),
                        ),
                      ),
                    ],
                  ],
                ],
                if (c.busy || _creating) const LinearProgressIndicator(),
                if (_invitationError != null)
                  Text(
                    _invitationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (c.error != null && c.error != _invitationError)
                  Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
