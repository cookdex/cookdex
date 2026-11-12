import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'components.dart';
import 'facelift_motion.dart';
import 'facelift_tokens.dart';

const _labels = {
  MotionGroup.tabs: 'Tab switches',
  MotionGroup.sheets: 'Sheets',
  MotionGroup.lists: 'List animations',
  MotionGroup.floating: 'Floating buttons',
  MotionGroup.cook: 'Cook mode steps',
  MotionGroup.star: 'Star pop',
  MotionGroup.recipeOpening: 'Recipe opening',
  MotionGroup.cookEntry: 'Cook mode entry',
};

Future<void> showDesignLab(BuildContext context) {
  final settings = FaceliftMotion.settingsOf(context)!;
  return showCookdexSheet<void>(
    context,
    child: ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Design lab', style: FaceliftTokens.sheetTitle(context)),
          for (final entry in _labels.entries) ...[
            Row(
              children: [
                Expanded(child: Text(entry.value)),
                Text('${settings.speed(entry.key).toStringAsFixed(2)}×'),
              ],
            ),
            Slider(
              inactiveColor: Theme.of(context).colorScheme.onSurfaceVariant
                  .withValues(alpha: .65),
              min: .5,
              max: 1.5,
              divisions: 20,
              value: settings.speed(entry.key),
              semanticFormatterCallback: (value) =>
                  '${entry.value}, ${value.toStringAsFixed(2)} times',
              onChanged: (value) => settings.setSpeed(entry.key, value),
            ),
          ],
          Row(
            children: [
              const Expanded(child: Text('Check-off delay')),
              Text('${settings.checkOffMs} ms'),
            ],
          ),
          Slider(
            min: 0,
            max: 1000,
            divisions: 20,
            value: settings.checkOffMs.toDouble(),
            semanticFormatterCallback: (value) =>
                '${value.round()} milliseconds',
            onChanged: (value) => settings.setCheckOffMs(value.round()),
          ),
          FilledButton.tonal(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: [
                    'Bottom bar: docked',
                    for (final entry in _labels.entries)
                      '${entry.value}: ${settings.speed(entry.key).toStringAsFixed(2)}×',
                    'Check-off delay: ${settings.checkOffMs} ms',
                  ].join('\n'),
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copy values'),
          ),
        ],
      ),
    ),
  );
}
