import 'package:flutter/material.dart';

import 'pixel_scroll.dart';

/// Presentation data only; snapshot files and validation belong to the store.
class LocalSnapshotEntry {
  const LocalSnapshotEntry({
    required this.id,
    required this.createdAt,
    required this.recipeCount,
    required this.omittedCount,
    required this.reason,
  });

  final String id;
  final DateTime createdAt;
  final int recipeCount;
  final int omittedCount;
  final String reason;
}

class SnapshotListing {
  const SnapshotListing({
    required this.entries,
    this.repeatedlyFailing = false,
  });

  final List<LocalSnapshotEntry> entries;
  final bool repeatedlyFailing;
}

class SnapshotsScreen extends StatefulWidget {
  const SnapshotsScreen({
    super.key,
    required this.load,
    required this.onRestore,
    required this.onExport,
  });

  final Future<SnapshotListing> Function() load;
  final Future<void> Function(LocalSnapshotEntry) onRestore;
  final Future<void> Function(LocalSnapshotEntry) onExport;

  @override
  State<SnapshotsScreen> createState() => _SnapshotsScreenState();
}

class _SnapshotsScreenState extends State<SnapshotsScreen> {
  SnapshotListing? _listing;
  bool _loading = true;
  bool _busy = false;
  bool _loadFailed = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final listing = await widget.load();
      if (mounted) setState(() => _listing = listing);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(LocalSnapshotEntry entry, {required bool restore}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await (restore ? widget.onRestore(entry) : widget.onExport(entry));
      if (mounted && restore) await _reload();
    } catch (_) {
      if (mounted) {
        setState(
          () => _actionError = restore
              ? 'Could not restore this snapshot. Try again.'
              : 'Could not export this snapshot. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _reason(String reason) => switch (reason) {
    'before_restore' || 'Before restore' => 'Before restore',
    'before_discard' || 'Before discarding' => 'Before discarding',
    'before_first_sync' || 'Before first sync' => 'Before first sync',
    _ => 'Automatic',
  };

  Widget _entry(BuildContext context, LocalSnapshotEntry entry) {
    final local = entry.createdAt.toLocal();
    final labels = MaterialLocalizations.of(context);
    final date = labels.formatMediumDate(local);
    final time = labels.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$date · $time',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${entry.recipeCount} ${entry.recipeCount == 1 ? 'recipe' : 'recipes'} · ${_reason(entry.reason)}',
            ),
            if (entry.omittedCount > 0) ...[
              const SizedBox(height: 8),
              Text(
                '${entry.omittedCount} ${entry.omittedCount == 1 ? 'recipe was' : 'recipes were'} omitted because they could not be safely backed up.',
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: _busy ? null : () => _act(entry, restore: true),
                  child: const Text('Restore'),
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: _busy ? null : () => _act(entry, restore: false),
                  child: const Text('Export ZIP'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Snapshots')),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: PixelListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Automatic snapshots save your changed recipe library once a day. They stay on this device only.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Keeps up to 7 daily and 4 weekly snapshots, within 256 MiB. Export a ZIP to keep a separate backup.',
              ),
              const SizedBox(height: 24),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_loadFailed) ...[
                const Text('Could not load snapshots.'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: _busy ? null : _reload,
                    child: const Text('Retry'),
                  ),
                ),
              ] else ...[
                if (_listing?.repeatedlyFailing ?? false) ...[
                  const Text(
                    'Automatic snapshots have not been saving. You can still export a recipe ZIP from Settings.',
                  ),
                  const SizedBox(height: 16),
                ],
                if (_actionError != null) ...[
                  Text(
                    _actionError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                if (_listing!.entries.isEmpty)
                  const Text(
                    'No snapshots yet. A snapshot will appear after your library changes.',
                  )
                else
                  for (final entry in _listing!.entries) _entry(context, entry),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
