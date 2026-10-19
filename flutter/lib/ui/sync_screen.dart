import 'pixel_scroll.dart';
import 'retained_screen.dart';
import 'navigation_feedback.dart';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../recipe_store.dart';
import '../src/rust/api.dart';
import '../sync_controller.dart';
import '../sync_presentation.dart';
import 'components.dart';
import 'pairing_screen.dart';
export 'pairing_screen.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key, required this.controller, required this.store});
  final SyncController controller;
  final RecipeStore store;

  Widget _group(BuildContext context, String title, List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(),
                    children[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      );

  Future<void> _rename(BuildContext context, SyncStatus status) async {
    final name = TextEditingController(text: status.name);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Device name'),
        content: PixelScrollScope(
          axis: Axis.horizontal,
          builder: (context) => TextField(
            scrollController: PrimaryScrollController.of(context),
            controller: name,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 100,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (name.text.trim().isNotEmpty) {
                Navigator.pop(context, name.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    name.dispose();
    if (value != null) await controller.configure(status.enabled, value);
  }

  Future<void> _pair(BuildContext context) async {
    await controller.pairing(true);
    if (!context.mounted) {
      await controller.pairing(false);
      return;
    }
    try {
      await Navigator.push<void>(
        context,
        cookdexRoute(
          context,
          builder: (_) => PairingScreen(controller: controller),
        ),
      );
    } finally {
      await controller.pairing(false);
    }
  }

  Widget _peerRow(BuildContext context, SyncPeer peer, SyncStatus status) =>
      ListTile(
        key: ValueKey('sync-peer-${peer.id}'),
        leading: _SyncDot(peerSyncColor(peer, status)),
        title: Text(peer.name),
        subtitle: Text(peerSyncText(peer, status)),
        trailing: const Icon(Symbols.chevron_right),
        minVerticalPadding: 12,
        onTap: () => Navigator.push<void>(
          context,
          cookdexRoute(
            context,
            builder: (_) => SyncDeviceDetailsScreen(
              controller: controller,
              deviceId: peer.id,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: Listenable.merge([controller, store]),
    builder: (context) {
      final status = controller.status;
      final presentation = syncPresentation(controller, store.conflicts.length);
      final failures = <String>{
        if (controller.error != null) controller.error!,
        if (status?.error != null) status!.error!,
        for (final report in status?.reports ?? <SyncReport>[])
          if (report.status == 'error')
            '${status!.peers.where((peer) => peer.id == report.id).firstOrNull?.name ?? report.name}: ${report.error ?? 'Transfer could not complete.'}',
      };
      return Scaffold(
        appBar: AppBar(title: const Text('Sync')),
        body: SafeArea(
          top: false,
          child: PixelListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (status?.rePairRequired == true)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pair your devices again',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sync security has been updated. Pair your devices again to keep syncing. Your recipes and other settings are unchanged.',
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: controller.busy
                              ? null
                              : controller.dismissPairingNotice,
                          child: const Text('Got it'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (status?.rePairRequired == true) const SizedBox(height: 24),
              _group(context, 'Status', [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final theme = Theme.of(context);
                          final label =
                              status == null && controller.error == null
                              ? 'Loading sync'
                              : presentation.label;
                          double textWidth(String text, TextStyle? style) {
                            final painter = TextPainter(
                              text: TextSpan(text: text, style: style),
                              textDirection: Directionality.of(context),
                              textScaler: MediaQuery.textScalerOf(context),
                            )..layout();
                            final width = painter.width;
                            painter.dispose();
                            return width;
                          }

                          final actionWidth =
                              textWidth(
                                'Sync now',
                                theme.textTheme.labelLarge,
                              ) +
                              32;
                          // Reserve the status dot and two 16dp row gaps.
                          final stack =
                              constraints.maxWidth <
                              textWidth(label, theme.textTheme.bodyLarge) +
                                  actionWidth +
                                  42;
                          final details = Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: theme.textTheme.bodyLarge),
                              const SizedBox(height: 4),
                              Text(
                                _statusDetails(status, presentation),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          );
                          final action = FilledButton.tonal(
                            key: const ValueKey('sync-now'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onPressed:
                                status?.enabled == true && !controller.busy
                                ? controller.manual
                                : null,
                            child: const Text(
                              'Sync now',
                              textAlign: TextAlign.center,
                            ),
                          );
                          if (stack) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    _SyncDot(presentation.color),
                                    const SizedBox(width: 16),
                                    Expanded(child: details),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: action,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              _SyncDot(presentation.color),
                              const SizedBox(width: 16),
                              Expanded(child: details),
                              const SizedBox(width: 16),
                              action,
                            ],
                          );
                        },
                      ),
                    ),
                    if (status == null && controller.error == null)
                      const LinearProgressIndicator(),
                  ],
                ),
              ]),
              if (store.conflicts.isNotEmpty || failures.isNotEmpty)
                _group(context, 'Needs attention', [
                  for (final conflict in store.conflicts)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final resolve = TextButton(
                          onPressed: () => Navigator.push<void>(
                            context,
                            cookdexRoute(
                              context,
                              builder: (_) => ConflictsScreen(
                                controller: controller,
                                store: store,
                                focusRecipeId: conflict.recipeId,
                              ),
                            ),
                          ),
                          child: const Text('Resolve'),
                        );
                        const subtitle = Text(
                          'Changed on more than one device. Choose what to keep.',
                        );
                        if (constraints.maxWidth < 600 &&
                            MediaQuery.textScalerOf(context).scale(14) > 20) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Symbols.merge),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Text(_conflictTitle(conflict)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                subtitle,
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: resolve,
                                ),
                              ],
                            ),
                          );
                        }
                        return ListTile(
                          leading: const Icon(Symbols.merge),
                          title: Text(_conflictTitle(conflict)),
                          subtitle: subtitle,
                          minVerticalPadding: 12,
                          trailing: resolve,
                        );
                      },
                    ),
                  for (final failure in failures)
                    ListTile(
                      leading: Icon(
                        Symbols.error,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(failure),
                      subtitle: Text(_failureAdvice(failure)),
                      minVerticalPadding: 12,
                    ),
                ]),
              if (status != null) ...[
                _group(context, 'This device', [
                  SwitchListTile(
                    secondary: const Icon(Symbols.sync),
                    title: const Text('Sync on this device'),
                    value: status.enabled,
                    onChanged: controller.busy
                        ? null
                        : (value) => controller.configure(value, status.name),
                  ),
                  ListTile(
                    leading: const Icon(Symbols.devices),
                    title: Text(status.name),
                    subtitle: const Text('Device name'),
                    trailing: const Icon(Symbols.edit),
                    minVerticalPadding: 12,
                    onTap: controller.busy
                        ? null
                        : () => _rename(context, status),
                  ),
                ]),
                _group(context, 'Paired devices', [
                  if (!status.peers.any((peer) => !peer.pairingPending))
                    const ListTile(
                      title: Text('No devices paired yet'),
                      subtitle: Text(
                        'Add your own devices to share one recipe book.',
                      ),
                      minVerticalPadding: 12,
                    ),
                  for (final peer in status.peers.where(
                    (peer) => !peer.pairingPending,
                  ))
                    _peerRow(context, peer, status),
                  ListTile(
                    key: const ValueKey('sync-add-device'),
                    leading: const Icon(Symbols.add),
                    title: const Text('Add a device'),
                    subtitle: !status.enabled
                        ? const Text('Turn on sync to pair your devices.')
                        : status.peers.length >= 16
                        ? const Text('Up to 16 devices can be paired.')
                        : null,
                    trailing: const Icon(Symbols.chevron_right),
                    minVerticalPadding: 12,
                    enabled: status.enabled,
                    onTap: status.enabled ? () => _pair(context) : null,
                  ),
                ]),
                if (status.peers.any((peer) => peer.pairingPending))
                  _group(context, 'Unfinished pairing', [
                    for (final peer in status.peers.where(
                      (peer) => peer.pairingPending,
                    ))
                      _peerRow(context, peer, status),
                  ]),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    title: Text(
                      'Technical details',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    children: [
                      ListTile(
                        title: const Text('Port'),
                        subtitle: Text('${status.port}'),
                      ),
                      ListTile(
                        title: const Text('Addresses'),
                        subtitle: SelectableText(
                          status.addresses.isEmpty
                              ? 'No local address available'
                              : status.addresses.join('\n'),
                        ),
                      ),
                      ListTile(
                        title: const Text('Device ID'),
                        subtitle: SelectableText(status.deviceId),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  String _statusDetails(SyncStatus? status, SyncPresentation presentation) {
    if (status == null && controller.error == null) {
      return 'Checking this device…';
    }
    if (presentation.label == 'Synced') {
      final peers = status!.peers
          .where((peer) => !peer.pairingPending)
          .toList();
      final times = peers.map((peer) => peer.lastSync).whereType<int>().toList()
        ..sort();
      final when = times.length == peers.length
          ? ' · ${readableSyncTime(times.first)}'
          : '';
      return '${peers.length} ${peers.length == 1 ? 'device' : 'devices'}$when';
    }
    if (presentation.label == 'Sync off') {
      return status?.enabled == true ? 'Add a device' : 'Turn on sync';
    }
    return switch (presentation.label) {
      'Not synced' => 'Waiting for devices',
      'Syncing' => 'Sharing changes…',
      'Sync failure' => 'See details below',
      'Sync conflict' =>
        '${store.conflicts.length} ${store.conflicts.length == 1 ? 'recipe needs' : 'recipes need'} a choice',
      _ => presentation.sentence,
    };
  }
}

class _SyncDot extends StatelessWidget {
  const _SyncDot(this.color);
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: syncColorForBrightness(color, Theme.of(context).brightness),
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );
}

String _failureAdvice(String reason) {
  final lower = reason.toLowerCase();
  if (lower.contains('update cookdex on the other device') ||
      lower.contains('this device needs an update') ||
      lower.contains('incompatible') ||
      lower.contains('update all cookdex devices')) {
    return 'After updating, open both apps and try again.';
  }
  if (lower.contains('storage') ||
      lower.contains('database') ||
      lower.contains('disk')) {
    return 'Check available storage on this device, then tap Sync now. If it continues, send a screenshot and app info.';
  }
  if (lower.contains('authentication') ||
      lower.contains('rejected') ||
      lower.contains('trust')) {
    return 'Open both apps on the same Wi-Fi and try Sync now. If the connection is still rejected, forget this device and pair it again.';
  }
  if (lower.contains('permission') || lower.contains('allow nearby')) {
    return 'Allow Nearby devices for cookdex in Android app settings, then tap Sync now.';
  }
  return 'Keep both apps open on the same Wi-Fi, then tap Sync now. If it keeps failing, send a screenshot and app info.';
}

String _conflictTitle(Conflict conflict) =>
    conflict.versions
        .map((version) => version.recipe?.fields.title)
        .whereType<String>()
        .firstOrNull ??
    'Deleted recipe';

class SyncDeviceDetailsScreen extends StatelessWidget {
  const SyncDeviceDetailsScreen({
    super.key,
    required this.controller,
    required this.deviceId,
  });
  final SyncController controller;
  final String deviceId;
  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: controller,
    builder: (context) {
      final status = controller.status;
      final peer = status?.peers
          .where((peer) => peer.id == deviceId)
          .firstOrNull;
      return Scaffold(
        appBar: AppBar(title: Text(peer?.name ?? 'Device details')),
        body: SafeArea(
          top: false,
          child: PixelListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (peer == null)
                const ListTile(title: Text('This device is no longer paired.'))
              else
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        leading: _SyncDot(peerSyncColor(peer, status!)),
                        title: Text(peer.name),
                        subtitle: Text(peerSyncText(peer, status)),
                        minVerticalPadding: 12,
                      ),
                      if (!peer.pairingPending) ...[
                        const Divider(),
                        ListTile(
                          title: const Text('Last sync'),
                          subtitle: Text(readableSyncTime(peer.lastSync)),
                          minVerticalPadding: 12,
                        ),
                      ],
                      const Divider(),
                      ListTile(
                        title: const Text('Address'),
                        subtitle: SelectableText(peer.address),
                        minVerticalPadding: 12,
                      ),
                      const Divider(),
                      ListTile(
                        leading: Icon(
                          Symbols.link_off,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          peer.pairingPending
                              ? 'Forget setup'
                              : 'Forget device',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        minVerticalPadding: 12,
                        enabled: !controller.busy,
                        onTap: controller.busy
                            ? null
                            : () async {
                                if (await confirmCookdex(
                                  context,
                                  title: 'Forget ${peer.name}?',
                                  action: 'Forget',
                                  content: Text(
                                    peer.pairingPending
                                        ? 'Remove this unfinished setup and any previous pairing with this device. Recipes already on each device stay there.'
                                        : 'These devices will stop sharing recipe changes. Recipes already on each device stay there.',
                                  ),
                                  destructive: true,
                                )) {
                                  await controller.forget(peer.id);
                                  if (context.mounted &&
                                      controller.error == null) {
                                    Navigator.pop(context);
                                  }
                                }
                              },
                      ),
                    ],
                  ),
                ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    controller.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class ConflictsScreen extends StatelessWidget {
  const ConflictsScreen({
    super.key,
    required this.controller,
    required this.store,
    this.focusRecipeId,
  });
  final SyncController controller;
  final RecipeStore store;
  final String? focusRecipeId;
  List<Conflict> get _conflicts => store.conflicts
      .where(
        (conflict) =>
            focusRecipeId == null || conflict.recipeId == focusRecipeId,
      )
      .toList();
  @override
  Widget build(BuildContext context) => VisibleListenableBuilder(
    listenable: Listenable.merge([controller, store]),
    builder: (context) => Scaffold(
      appBar: AppBar(title: const Text('Resolve conflicts')),
      body: PixelListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_conflicts.isEmpty) const Text('No unresolved conflicts.'),
          if (controller.error != null)
            Text(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final conflict in _conflicts)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conflict.versions
                              .map((v) => v.recipe?.fields.title)
                              .whereType<String>()
                              .firstOrNull ??
                          'Deleted recipe',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final (index, version) in conflict.versions.indexed)
                      ExpansionTile(
                        title: Text(
                          version.recipe == null
                              ? 'Version ${index + 1} · Deletion'
                              : 'Version ${index + 1} · ${_readableRecipeDate(version.recipe!.updatedAt)}',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: SelectableText(
                              version.recipe == null
                                  ? 'Deleted ${_readableRecipeDate(version.deletedAt)}'
                                  : _recipeText(version.recipe!),
                            ),
                          ),
                          TextButton(
                            style: version.recipe == null
                                ? TextButton.styleFrom(
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .error,
                                  )
                                : null,
                            onPressed: controller.busy
                                ? null
                                : () async {
                                    final deletion = version.recipe == null;
                                    if (await confirmCookdex(
                                      context,
                                      title: deletion
                                          ? 'Use deletion?'
                                          : 'Use this version?',
                                      action: deletion
                                          ? 'Use deletion'
                                          : 'Use version',
                                      destructive: deletion,
                                    )) {
                                      await controller.resolve(
                                        conflict,
                                        ConflictChoice.version(id: version.id),
                                      );
                                    }
                                  },
                            child: Text(
                              version.recipe == null
                                  ? 'Use deletion'
                                  : 'Use version',
                            ),
                          ),
                        ],
                      ),
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : () async {
                              if (await confirmCookdex(
                                context,
                                title: 'Keep all recipe versions?',
                                action: 'Keep all',
                              )) {
                                await controller.resolve(
                                  conflict,
                                  const ConflictChoice.keepAll(),
                                );
                              }
                            },
                      child: const Text('Keep all'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
  static String _recipeText(Recipe r) {
    final f = r.fields;
    String fraction(int numerator, int denominator) =>
        denominator == 1 ? '$numerator' : '$numerator/$denominator';
    String amount(Amount a) => switch (a) {
      Amount_Rational(:final numerator, :final denominator) =>
        denominator == 1 ? '$numerator' : '$numerator/$denominator',
      Amount_Range(
        :final lowerNumerator,
        :final lowerDenominator,
        :final upperNumerator,
        :final upperDenominator,
      ) =>
        '${fraction(lowerNumerator, lowerDenominator)}–${fraction(upperNumerator, upperDenominator)}',
      Amount_ToTaste() => 'to taste',
      Amount_Unspecified() => '',
    };
    return '${f.title}\n${f.description}\nServings: ${f.servings}\nPrep: ${f.prepTime}\nCook: ${f.cookTime}\nTotal: ${f.totalTime}\nTags: ${f.tags.join(', ')}\nFavorite: ${r.favorite}\n\nIngredients\n${f.ingredients.map((i) => '${i.section.isEmpty ? '' : '[${i.section}] '}${amount(i.amount)} ${i.unit} ${i.name}${i.optional ? ' (optional)' : ''}${i.prepNote.isEmpty ? '' : ', ${i.prepNote}'}').join('\n')}\n\nSteps\n${f.steps.indexed.map((e) => '${e.$1 + 1}. ${e.$2}').join('\n')}\n\nNotes\n${f.notes}\nSource: ${f.source}\nCreated: ${_readableRecipeDate(r.createdAt)}\nUpdated: ${_readableRecipeDate(r.updatedAt)}\nRevision: ${r.revision}';
  }
}

String _readableRecipeDate(String? value) {
  final date = value == null ? null : DateTime.tryParse(value);
  return date == null
      ? 'Date unavailable'
      : readableSyncTime(date.millisecondsSinceEpoch ~/ 1000);
}
