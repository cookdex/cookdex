import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../fraction_display.dart';
import '../recipe_store.dart';
import '../src/rust/api.dart';
import 'components.dart';
import 'facelift_tokens.dart';
import 'page_headings.dart';
import 'navigation_feedback.dart';
import 'pixel_scroll.dart';

String _errorMessage(Object error, String fallback) =>
    error is ServiceError ? error.message : fallback;

/// Close the chooser before opening the preview so Back returns to Shopping.
Future<({ShoppingUndo undo, String title})?> showRecipesOnList(
  BuildContext context, {
  required RecipeStore store,
}) async {
  final recipe = await showCookdexSheet<ShoppingRecipe>(
    context,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    child: RecipesOnListSheet(store: store),
  );
  if (recipe == null || !context.mounted) return null;
  final undo = await Navigator.of(context).push<ShoppingUndo>(
    cookdexRoute<ShoppingUndo>(
      context,
      builder: (_) => _RecipeRemovalPreview(store: store, recipe: recipe),
    ),
  );
  return undo == null ? null : (undo: undo, title: recipe.title);
}

class RecipesOnListSheet extends StatefulWidget {
  const RecipesOnListSheet({super.key, required this.store});
  final RecipeStore store;

  @override
  State<RecipesOnListSheet> createState() => _RecipesOnListSheetState();
}

class _RecipesOnListSheetState extends State<RecipesOnListSheet> {
  List<ShoppingRecipe>? _recipes;
  String? _error;
  int _request = 0;
  int _generation = -1;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (_generation != widget.store.generation) _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    _generation = widget.store.generation;
    setState(() => _error = null);
    try {
      final recipes = await widget.store.shoppingRecipes();
      if (mounted && request == _request) {
        setState(() => _recipes = recipes);
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _error = _errorMessage(
            error,
            'Could not load recipes on this list.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Recipes on this list', style: FaceliftTokens.sheetTitle(context)),
      const SizedBox(height: 16),
      if (_error != null)
        _Retry(message: _error!, onRetry: _load)
      else if (_recipes == null)
        const Center(child: CircularProgressIndicator())
      else if (_recipes!.isEmpty)
        Text(
          'Nothing to remove. Checked, edited and older items stay on your list.',
          style: FaceliftTokens.tileSubtitle(context),
        )
      else
        for (final (index, recipe) in _recipes!.indexed) ...[
          if (index > 0) const SizedBox(height: FaceliftTokens.tileGap),
          FaceliftSheetTile(
            key: ValueKey('shopping-recipe-${recipe.recipeId}'),
            title: recipe.title,
            subtitle:
                '${recipe.itemCount} ${recipe.itemCount == 1 ? 'item' : 'items'}',
            icon: Symbols.menu_book,
            onTap: () => Navigator.pop(context, recipe),
          ),
        ],
    ],
  );
}

class _RecipeRemovalPreview extends StatefulWidget {
  const _RecipeRemovalPreview({required this.store, required this.recipe});
  final RecipeStore store;
  final ShoppingRecipe recipe;

  @override
  State<_RecipeRemovalPreview> createState() => _RecipeRemovalPreviewState();
}

class _RecipeRemovalPreviewState extends State<_RecipeRemovalPreview> {
  ShoppingRemovalPreview? _preview;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _stale = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _stale = false;
      _preview = null;
    });
    try {
      final preview = await widget.store.previewShoppingRemoval(
        widget.recipe.recipeId,
      );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = _errorMessage(error, 'Could not load this preview.'),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove() async {
    if (_busy || _loading || _stale || _preview == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final undo = await widget.store.removeShoppingRecipe(_preview!);
      if (mounted) Navigator.pop(context, undo);
    } catch (error) {
      if (mounted) {
        setState(() {
          _stale = error is ServiceError && error.code == ErrorCode.staleWrite;
          _error = _stale
              ? 'Your shopping list changed. Refresh the preview before removing items.'
              : _errorMessage(error, 'Could not remove these recipe items.');
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final hasChanges =
        preview?.lines.any(
          (line) => line.action == 'remove' || line.action == 'reduce',
        ) ??
        false;
    final canRemove = !_busy && !_loading && !_stale && hasChanges;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        key: const Key('shopping-removal-preview'),
        appBar: pageHeadingBar(
          context,
          title: preview?.title ?? widget.recipe.title,
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = ((constraints.maxWidth - 640) / 2).clamp(
                0.0,
                double.infinity,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: PixelSingleChildScrollView(
                      key: const Key('shopping-removal-scroll'),
                      padding: EdgeInsets.fromLTRB(
                        side + 16,
                        12,
                        side + 16,
                        24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else ...[
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _Retry(
                                  message: _error!,
                                  onRetry: _busy ? null : _load,
                                  label: preview == null
                                      ? 'Retry'
                                      : 'Refresh preview',
                                ),
                              ),
                            if (preview != null) ...[
                              if (!hasChanges)
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 16),
                                  child: Text('No items can be removed.'),
                                ),
                              for (final (action, title) in [
                                ('remove', 'Comes off'),
                                ('reduce', 'Gets smaller'),
                                ('keep', 'Stays'),
                              ])
                                if (preview.lines.any(
                                  (line) => line.action == action,
                                ))
                                  _PreviewSection(
                                    title: title,
                                    action: action,
                                    lines: preview.lines
                                        .where((line) => line.action == action)
                                        .toList(),
                                  ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(side + 16, 8, side + 16, 16),
                    child: FilledButton(
                      key: const Key('confirm-shopping-recipe-removal'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                        foregroundColor: Theme.of(context).colorScheme.onError,
                      ),
                      onPressed: canRemove ? _remove : null,
                      child: Text(_busy ? 'Removing…' : 'Remove from list'),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({
    required this.title,
    required this.action,
    required this.lines,
  });
  final String title, action;
  final List<ShoppingRemovalLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: FaceliftTokens.categoryTitle(context)),
          ),
          const SizedBox(height: 8),
          Material(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, line) in lines.indexed) ...[
                  if (index > 0) const Divider(indent: 16, endIndent: 16),
                  Padding(
                    key: ValueKey('shopping-removal-line-${line.id}'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text.rich(
                          key: ValueKey('shopping-removal-label-${line.id}'),
                          TextSpan(
                            children: [
                              if (action == 'reduce') ...[
                                WidgetSpan(
                                  alignment: PlaceholderAlignment.baseline,
                                  baseline: TextBaseline.alphabetic,
                                  child: _ReductionAmount(line: line),
                                ),
                                const TextSpan(text: ' '),
                              ] else if (line.before.isNotEmpty)
                                TextSpan(
                                  text:
                                      '${displayFractions(line.before).replaceAll(' ', '\u00a0')} ',
                                  semanticsLabel:
                                      '${spokenFractions(line.before)} ',
                                  style: amountDisplayStyle,
                                ),
                              TextSpan(
                                text: line.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        if (line.reason.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            line.reason,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One inline group keeps the two amounts together while the name can wrap.
/// The bundled icon supplies the arrow independently of the fraction font.
class _ReductionAmount extends StatelessWidget {
  const _ReductionAmount({required this.line});
  final ShoppingRemovalLine line;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium
        ?.merge(amountDisplayStyle);
    return Semantics(
      key: ValueKey('shopping-removal-amounts-${line.id}'),
      label:
          '${spokenFractions(line.before)} to ${spokenFractions(line.after ?? '')}',
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayFractions(line.before),
                style: style,
                // WidgetSpan applies the enclosing paragraph's text scale.
                textScaler: TextScaler.noScaling,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Symbols.arrow_right_alt, size: 20),
              ),
              Text(
                displayFractions(line.after ?? ''),
                style: style,
                textScaler: TextScaler.noScaling,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({
    required this.message,
    required this.onRetry,
    this.label = 'Retry',
  });
  final String message, label;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      TextButton(onPressed: onRetry, child: Text(label)),
    ],
  );
}
