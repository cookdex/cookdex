import 'page_headings.dart';
import 'pixel_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../src/rust/api.dart';
import '../recipe_store.dart';
import '../export_service.dart';
import 'feedback.dart';
import 'facelift_motion.dart';
import 'facelift_tokens.dart';
import 'recipe_metadata.dart';
import 'facelift_sheet_tiles.dart';

export 'facelift_sheet_tiles.dart';

part 'recipe_action_sheets.dart';

/// Future editor/import routes use this shell; fields never request focus here.
/// A pushed route covers the tab shell and returns to its exact origin on Back.
class CookdexFormScaffold extends StatelessWidget {
  const CookdexFormScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onSave,
    this.bottomNavigationBar,
    this.actions = const [],
  });
  final String title;
  final Widget child;
  final VoidCallback? onSave;
  final Widget? bottomNavigationBar;
  final List<Widget> actions;
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
        appBar: pageHeadingBar(
          context,
          leading: IconButton(
            icon: const Icon(Symbols.arrow_back),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: title,
          actions: [
            ...actions,
            if (onSave != null)
              TextButton(onPressed: onSave, child: const Text('Save')),
          ],
        ),
        body: SafeArea(top: false, child: child),
        bottomNavigationBar: bottomNavigationBar,
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
      borderRadius: BorderRadius.circular(FaceliftTokens.tagRadius),
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

Future<T?> showCookdexSheet<T>(
  BuildContext context, {
  required Widget child,
  Color? backgroundColor,
  bool useRootNavigator = false,
}) {
  final duration = FaceliftMotion.duration(context, MotionGroup.sheets);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    constraints: const BoxConstraints(maxWidth: 560),
    requestFocus: true,
    sheetAnimationStyle: AnimationStyle(
      duration: duration,
      reverseDuration: duration,
    ),
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
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: FaceliftTokens.sheetHeadingInset,
                      bottom:
                          MediaQuery.viewInsetsOf(sheetContext).bottom +
                          FaceliftTokens.sheetBottom,
                    ),
                    child: PixelSingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FaceliftTokens.sheetSide,
                      ),
                      child: child,
                    ),
                  ),
                  Align(
                    alignment: Alignment.topCenter,
                    heightFactor: 1,
                    child: Semantics(
                      button: true,
                      label: MaterialLocalizations.of(sheetContext)
                          .modalBarrierDismissLabel,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.pop(sheetContext),
                        child: SizedBox.square(
                          dimension: kMinInteractiveDimension,
                          child: Align(
                            alignment: const Alignment(0, -.45),
                            child: Container(
                              width: 32,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .onSurfaceVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

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
  backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
  child: Builder(
    builder: (sheetContext) {
      const groups = [
        (
          'Recipe file',
          'Best for other cookdex users. Open the .txt file with cookdex.',
          [
            (
              ExportAction.shareFile,
              'Send as .txt file',
              'Attach a recipe file to a message',
              Symbols.attach_file,
            ),
            (
              ExportAction.save,
              'Save .txt file',
              'Choose where to save the recipe file',
              Symbols.download,
            ),
          ],
        ),
        (
          'Plain text',
          'For anyone without cookdex, or to paste the whole recipe.',
          [
            (
              ExportAction.share,
              'Send as message',
              'Share recipe text in another app',
              Symbols.chat,
            ),
            (
              ExportAction.copy,
              'Copy text',
              'Copy the recipe to your clipboard',
              Symbols.content_copy,
            ),
          ],
        ),
      ];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Share', style: FaceliftTokens.sheetTitle(context)),
          for (final group in groups) ...[
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                group.$1,
                style: FaceliftTokens.categoryTitle(context),
              ),
            ),
            const SizedBox(height: 2),
            Text(group.$2, style: FaceliftTokens.tileSubtitle(context)),
            for (final choice in group.$3) ...[
              const SizedBox(height: FaceliftTokens.tileGap),
              FaceliftSheetTile(
                title: choice.$2,
                subtitle: choice.$3,
                icon: choice.$4,
                onTap: () => Navigator.of(sheetContext).pop(choice.$1),
              ),
            ],
          ],
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
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    child: _RecipeActionChoices(recipe: recipe, store: store),
  );
  if (choice == null || !context.mounted) return;
  if (choice == 'delete') {
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

/// Full-sized search actions outside the text field's focus/keyboard gesture.
class SearchFieldActions extends StatelessWidget {
  const SearchFieldActions({
    super.key,
    required this.controller,
    required this.onClear,
    this.onOptions,
  });
  final TextEditingController controller;
  final VoidCallback onClear;
  final VoidCallback? onOptions;
  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextFieldTapRegion(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (value.text.isNotEmpty)
                IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onClear();
                  },
                  icon: const Icon(Symbols.close),
                ),
              if (value.text.isNotEmpty && onOptions != null)
                const SizedBox(width: 8),
              if (onOptions != null)
                IconButton(
                  tooltip: 'Search fields',
                  onPressed: onOptions,
                  icon: const Icon(Symbols.tune),
                ),
            ],
          ),
        ),
      );
}

/// Outlined fields paint their floating label above their layout box. Reserve
/// that space inside dialog scroll content, including enlarged system text.
class DialogFieldPadding extends StatelessWidget {
  const DialogFieldPadding({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: MediaQuery.textScalerOf(context).scale(12)),
    child: child,
  );
}
