import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../recipe_store.dart';
import '../src/rust/api.dart' show ShoppingEdit;
import '../staples.dart';
import 'components.dart';
import 'navigation_feedback.dart';
import 'page_headings.dart';
import 'pixel_scroll.dart';

Future<void> openStaples(BuildContext context, {required RecipeStore store}) =>
    Navigator.of(context, rootNavigator: true).push<void>(
      cookdexRoute<void>(context, builder: (_) => StaplesScreen(store: store)),
    );

class StaplesScreen extends StatefulWidget {
  const StaplesScreen({super.key, required this.store});
  final RecipeStore store;

  @override
  State<StaplesScreen> createState() => _StaplesScreenState();
}

enum _StapleAction { rename, remove }

class _StaplesScreenState extends State<StaplesScreen> {
  String? _adding, _failed;

  Future<void> _edit([String? previous]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _StapleNameDialog(
        initial: previous,
        existing: widget.store.preferences.staples,
      ),
    );
    if (!mounted || name == null) return;
    final latest = widget.store.preferences.staples;
    if (previous == null) {
      if (latest.any((n) => n.toLowerCase() == name.toLowerCase())) return;
      widget.store.preferences.setStaples([...latest, name]);
    } else {
      widget.store.preferences.setStaples([
        for (final value in latest) value == previous ? name : value,
      ]);
    }
  }

  Future<void> _remove(String name) async {
    final remove = await confirmCookdex(
      context,
      title: 'Remove $name?',
      action: 'Remove',
      destructive: true,
    );
    if (!mounted || !remove) return;
    widget.store.preferences.setStaples([
      for (final value in widget.store.preferences.staples)
        if (value != name) value,
    ]);
  }

  Future<void> _restock(String name) async {
    if (_adding != null ||
        uncheckedStapleMatch(name, widget.store.shopping) != null) {
      return;
    }
    setState(() {
      _adding = name;
      _failed = null;
    });
    try {
      await widget.store.editShopping(
        ShoppingEdit.addManualItems(names: [name]),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = name);
    } finally {
      if (mounted) setState(() => _adding = null);
    }
  }

  Widget _row(String name) {
    final colors = Theme.of(context).colorScheme;
    final match = uncheckedStapleMatch(name, widget.store.shopping);
    final adding = _adding == name;
    final label = name;
    final status = _failed == name
        ? 'Could not add. Try again.'
        : adding
        ? 'Adding to shopping list…'
        : match != null
        ? 'On your list'
        : null;
    return ListTile(
      key: ValueKey('staple-$name'),
      minTileHeight: 56,
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      title: Text(label),
      onTap: _adding == null ? () => _edit(name) : null,
      subtitle: status == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Text(
                status,
                style: _failed == name ? TextStyle(color: colors.error) : null,
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: match != null
                ? '$label is on your list'
                : 'Add $label to shopping list',
            onPressed: match != null || _adding != null
                ? null
                : () => _restock(name),
            icon: adding
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    match != null ? Symbols.check : Symbols.add_shopping_cart,
                    color: match != null ? colors.primary : null,
                  ),
          ),
          PopupMenuButton<_StapleAction>(
            tooltip: '$label options',
            enabled: _adding == null,
            icon: const Icon(Symbols.more_vert),
            onSelected: (action) => switch (action) {
              _StapleAction.rename => _edit(name),
              _StapleAction.remove => _remove(name),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _StapleAction.rename,
                child: Text('Rename'),
              ),
              PopupMenuItem(
                value: _StapleAction.remove,
                child: Text('Remove', style: TextStyle(color: colors.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: pageHeadingBar(context, title: 'Staples'),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 608),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _adding == null ? () => _edit() : null,
                icon: const Icon(Symbols.add),
                label: const Text('Add staple'),
              ),
            ),
          ),
        ),
      ),
    ),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([widget.store, widget.store.preferences]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 640) / 2).clamp(
              0.0,
              double.infinity,
            );
            return PixelListView(
              padding: EdgeInsets.fromLTRB(side, 0, side, 16),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    "Things you usually have on hand. They start unticked when you add a recipe's ingredients to your list, and Smart Create doesn't count them as things to buy.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (widget.store.preferences.staples.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    child: Text('No staples yet'),
                  ),
                for (final name in widget.store.preferences.staples) _row(name),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _StapleNameDialog extends StatefulWidget {
  const _StapleNameDialog({this.initial, required this.existing});
  final String? initial;
  final List<String> existing;

  @override
  State<_StapleNameDialog> createState() => _StapleNameDialogState();
}

class _StapleNameDialogState extends State<_StapleNameDialog> {
  late final _name = TextEditingController(text: widget.initial ?? '');
  String? _error;

  void _save() {
    final value = _name.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter a staple name.');
    } else if (widget.existing.any(
      (name) =>
          name != widget.initial && name.toLowerCase() == value.toLowerCase(),
    )) {
      setState(() => _error = 'This staple is already saved.');
    } else {
      Navigator.pop(context, value);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.initial == null ? 'Add staple' : 'Rename staple'),
    content: DialogFieldPadding(
      child: TextField(
        controller: _name,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _save,
        child: Text(widget.initial == null ? 'Add' : 'Save'),
      ),
    ],
  );
}
