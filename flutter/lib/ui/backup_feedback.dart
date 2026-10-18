import 'package:flutter/material.dart';

import 'feedback.dart';

Future<void> showBackupSaved(BuildContext context, int omitted) async {
  if (omitted == 0) {
    showFeedback(context, 'Recipe ZIP saved');
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Recipe ZIP saved'),
      scrollable: true,
      content: Text(
        '$omitted set-aside ${omitted == 1 ? 'recipe was' : 'recipes were'} left out because they could not be read safely. This ZIP contains only readable recipes. Keep any older backups you may need.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

Future<void> showCookbookSaved(BuildContext context, int omitted) async {
  if (omitted == 0) {
    showFeedback(context, 'Cookbook saved');
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Cookbook saved'),
      scrollable: true,
      content: Text(
        '$omitted set-aside ${omitted == 1 ? 'recipe was' : 'recipes were'} left out because they could not be read safely. This cookbook contains only readable recipes. Keep any older backups you may need.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}
