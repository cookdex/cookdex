import 'package:flutter/material.dart';

import '../import_diagnostics.dart';
import 'feedback.dart';
import 'pixel_scroll.dart';

Future<void> showLastSmartRecord(
  BuildContext context, {
  required String feature,
  required String? record,
  required Future<void> Function() clear,
}) {
  final message = record == null
      ? 'No $feature has been recorded.'
      : redactImportDiagnostic(record);
  var clearing = false;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, update) => PopScope(
        canPop: !clearing,
        child: AlertDialog(
          title: Text('Last $feature'),
          content: SizedBox(
            width: 640,
            child: PixelSingleChildScrollView(child: SelectableText(message)),
          ),
          actions: [
            if (record != null)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: clearing
                    ? null
                    : () async {
                        if (clearing) return;
                        update(() => clearing = true);
                        try {
                          await clear();
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (_) {
                          if (!dialogContext.mounted) return;
                          update(() => clearing = false);
                          showFeedback(
                            dialogContext,
                            'Could not clear the last $feature.',
                            kind: FeedbackKind.error,
                          );
                        }
                      },
                child: const Text('Clear record'),
              ),
            TextButton(
              onPressed: clearing ? null : () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}
