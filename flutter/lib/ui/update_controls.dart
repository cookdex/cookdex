import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../update_checker.dart';
import 'components.dart';

class UpdateSettingsPanel extends StatelessWidget {
  const UpdateSettingsPanel({
    super.key,
    required this.controller,
    required this.openPage,
  });
  final UpdateController controller;
  final Future<void> Function(String) openPage;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const Key('check-updates'),
          leading: const Icon(Symbols.refresh),
          title: Text(
            controller.state == UpdateCheckState.checking
                ? 'Checking for updates…'
                : 'Check for updates',
          ),
          minVerticalPadding: 12,
          hoverColor: Colors.transparent,
          onTap: controller.state == UpdateCheckState.checking
              ? null
              : () => unawaited(controller.check()),
        ),
        SwitchListTile(
          title: const Text('Check automatically'),
          subtitle: const Text('Checks GitHub once a day.'),
          value: controller.preferences.checkUpdatesAutomatically,
          onChanged: controller.setAutomatic,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? null
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? null
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (controller.state == UpdateCheckState.current ||
            controller.state == UpdateCheckState.error)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              controller.state == UpdateCheckState.error
                  ? updateCheckError
                  : "You're up to date (${controller.currentVersion})",
            ),
          ),
        if (controller.state == UpdateCheckState.available &&
            controller.release != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: UpdateDetails(
              release: controller.release!,
              openPage: openPage,
            ),
          ),
      ],
    ),
  );
}

class UpdateDetails extends StatefulWidget {
  const UpdateDetails({
    super.key,
    required this.release,
    required this.openPage,
  });
  final PublishedRelease release;
  final Future<void> Function(String) openPage;
  @override
  State<UpdateDetails> createState() => _UpdateDetailsState();
}

class _UpdateDetailsState extends State<UpdateDetails> {
  bool _openFailed = false;
  Future<void> _open() async {
    try {
      await widget.openPage(widget.release.page.toString());
      if (mounted) setState(() => _openFailed = false);
    } catch (_) {
      if (mounted) setState(() => _openFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'cookdex ${widget.release.version} is available',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      if (widget.release.notes.isNotEmpty) ...[
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: SingleChildScrollView(
            primary: false,
            child: Text(widget.release.notes, key: const Key('release-notes')),
          ),
        ),
      ],
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: _open,
        icon: const Icon(Symbols.open_in_new),
        label: const Text('Open release page'),
      ),
      if (_openFailed)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text("Couldn't open the release page."),
        ),
    ],
  );
}

class UpdateNotice extends StatelessWidget {
  const UpdateNotice({
    super.key,
    required this.controller,
    required this.openPage,
  });
  final UpdateController controller;
  final Future<void> Function(String) openPage;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final release = controller.notice;
      if (release == null) return const SizedBox.shrink();
      return Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            key: const Key('update-notice'),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 4,
                top: 4,
                bottom: 4,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text('cookdex ${release.version} is available'),
                  ),
                  TextButton(
                    onPressed: () => showCookdexSheet<void>(
                      context,
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: UpdateDetails(
                            release: release,
                            openPage: openPage,
                          ),
                        ),
                      ),
                    ),
                    child: const Text('View'),
                  ),
                  IconButton(
                    tooltip: 'Dismiss update',
                    onPressed: controller.dismissNotice,
                    icon: const Icon(Symbols.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
