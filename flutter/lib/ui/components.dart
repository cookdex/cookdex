import 'pixel_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../src/rust/api.dart';
import '../recipe_store.dart';
import '../export_service.dart';
import 'feedback.dart';

/// Future editor/import routes use this shell; fields never request focus here.
/// A pushed route covers the tab shell and returns to its exact origin on Back.
class CookdexFormScaffold extends StatelessWidget {
  const CookdexFormScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onSave,
  });
  final String title;
  final Widget child;
  final VoidCallback? onSave;
  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
    },
    child: Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) {
            Navigator.of(context).maybePop();
            return null;
          },
        ),
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Symbols.arrow_back),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(title),
          actions: [
            if (onSave != null)
              TextButton(onPressed: onSave, child: const Text('Save')),
          ],
        ),
        body: SafeArea(top: false, child: child),
      ),
    ),
  );
}

class TonalTag extends StatelessWidget {
  const TonalTag(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ),
  );
}

Future<T?> showCookdexSheet<T>(BuildContext context, {required Widget child}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      requestFocus: true,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (sheetContext) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                Navigator.of(sheetContext).pop();
                return null;
              },
            ),
          },
          child: FocusTraversalGroup(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .85,
              ),
              child: SafeArea(
                top: false,
                child: PixelSingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 12,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );

void showDeferred(BuildContext context, String feature) {
  showFeedback(context, '$feature is coming in a later migration chunk.');
}

void showUndo(
  BuildContext context, {
  required String message,
  required VoidCallback onUndo,
}) {
  showFeedback(context, message, onUndo: onUndo);
}

Future<bool> confirmCookdex(
  BuildContext context, {
  required String title,
  required String action,
  Widget? content,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: content,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: destructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// The setup replacement warning stays scrollable at large text sizes.
Future<bool> confirmRestore(
  BuildContext context,
  RestoreReport report,
) => confirmCookdex(
  context,
  title: 'Restore recipe ZIP?',
  action: 'Restore',
  content: PixelSingleChildScrollView(
    child: Text(
      '${report.added} new · ${report.updated} updated · ${report.skipped} skipped'
      '${report.shoppingSetup ? '\nShopping categories, aisle order and remembered placements on this device will be replaced by the backup.' : ''}'
      '${report.conflicts.isEmpty ? '' : '\n${report.conflicts.length} ${report.conflicts.length == 1 ? 'conflict' : 'conflicts'} will be kept unchanged.'}',
    ),
  ),
);

/// Android and Windows both provide native message and file sharing.
Future<ExportAction?> showShareOptions(
  BuildContext context, {
  required bool isAndroid,
}) => showCookdexSheet<ExportAction>(
  context,
  child: Builder(
    builder: (sheetContext) {
      Widget option(ExportAction action, String label, IconData icon) =>
          ListTile(
            leading: Icon(icon),
            title: Text(label),
            minVerticalPadding: 12,
            onTap: () => Navigator.of(sheetContext).pop(action),
          );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Share',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          option(ExportAction.share, 'Send as message', Symbols.chat),
          option(
            ExportAction.shareFile,
            'Send as .txt file',
            Symbols.attach_file,
          ),
          option(ExportAction.copy, 'Copy text', Symbols.content_copy),
          option(ExportAction.save, 'Save .txt file', Symbols.download),
        ],
      );
    },
  ),
);

Future<void> showRecipeActions({
  required BuildContext context,
  required RecipeStore store,
  required RecipeSummary recipe,
  VoidCallback? onDeleted,
  VoidCallback? onEdit,
  Future<void> Function(String choice)? onAction,
}) async {
  final choice = await showCookdexSheet<String>(
    context,
    child: Builder(
      builder: (sheetContext) {
        Widget item(
          String key,
          String title,
          IconData icon, {
          bool destructive = false,
        }) => ListTile(
          leading: Icon(
            icon,
            color: destructive ? Theme.of(context).colorScheme.error : null,
          ),
          title: Text(
            title,
            style: destructive
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null,
          ),
          onTap: () => Navigator.of(sheetContext).pop(key),
          minVerticalPadding: 12,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                recipe.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            item('select', 'Select', Symbols.check_box),
            item('edit', 'Edit', Symbols.edit),
            item('share', 'Share', Symbols.share),
            item('shopping', 'Add to shopping list', Symbols.shopping_cart),
            item(
              'favorite',
              recipe.favorite ? 'Unfavorite' : 'Favorite',
              recipe.favorite ? Symbols.star : Symbols.star_outline,
            ),
            item('delete', 'Delete', Symbols.delete, destructive: true),
          ],
        );
      },
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'favorite') {
    try {
      await store.toggleFavorite(recipe.id);
    } catch (_) {
      if (context.mounted) {
        showFeedback(
          context,
          'Could not update favorite.',
          kind: FeedbackKind.error,
        );
      }
    }
  } else if (choice == 'delete') {
    if (!await confirmCookdex(
      context,
      title: 'Delete this recipe?',
      action: 'Delete',
      destructive: true,
      content: Text(recipe.title),
    )) {
      return;
    }
    try {
      await store.deleteRecipe(recipe.id);
      onDeleted?.call();
    } catch (_) {
      if (context.mounted) {
        showFeedback(
          context,
          'Could not delete recipe.',
          kind: FeedbackKind.error,
        );
      }
    }
  } else if (choice == 'edit' && onEdit != null) {
    onEdit();
  } else if (onAction != null) {
    await onAction(choice);
  } else {
    const labels = {
      'edit': 'Recipe editing',
      'share': 'Sharing',
      'copy': 'Copy text',
      'save': 'Save text',
      'shopping': 'Shopping list',
    };
    showDeferred(context, labels[choice] ?? 'This action');
  }
}
