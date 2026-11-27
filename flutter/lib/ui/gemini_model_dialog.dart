import 'package:flutter/material.dart';

import '../create_preferences.dart';
import 'pixel_scroll.dart';

typedef GeminiModelSelection = ({
  String model,
  String thinking,
  bool useRecommended,
});

/// Shared pending model selection; the caller owns its recommended defaults.
class GeminiModelDialog extends StatefulWidget {
  const GeminiModelDialog({
    super.key,
    required this.title,
    required this.model,
    required this.thinking,
    required this.recommendedModel,
    required this.recommendedThinking,
    this.useRecommended = false,
  });

  final String title, model, thinking;
  final String recommendedModel, recommendedThinking;
  final bool useRecommended;

  @override
  State<GeminiModelDialog> createState() => _GeminiModelDialogState();
}

class _GeminiModelDialogState extends State<GeminiModelDialog> {
  late final model = TextEditingController(text: widget.model);
  static const models = CreatePreferences.modelNames;
  late String choice = models.containsKey(widget.model)
      ? widget.model
      : 'custom';
  late String thinking = widget.thinking;
  late bool useRecommended = widget.useRecommended;

  void updateModel() {
    if (!CreatePreferences.thinkingLevels(model.text.trim())
        .contains(thinking)) {
      thinking = 'default';
    }
    setState(() {});
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          itemHeight: null,
          isDense: false,
          initialValue: choice,
          key: ValueKey(choice),
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Model'),
          items: [
            for (final entry in models.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(
                  CreatePreferences.isPaidModel(entry.key)
                      ? '${entry.value} (paid key)'
                      : entry.value,
                ),
              ),
            const DropdownMenuItem(
              value: 'custom',
              child: Text('Custom model ID'),
            ),
          ],
          onChanged: (value) {
            useRecommended = false;
            choice = value!;
            model.text = choice == 'custom' ? '' : choice;
            updateModel();
          },
        ),
        if (choice == 'custom') ...[
          const SizedBox(height: 16),
          PixelScrollScope(
            axis: Axis.horizontal,
            builder: (context) => TextField(
              scrollController: PrimaryScrollController.of(context),
              controller: model,
              onChanged: (_) {
                useRecommended = false;
                updateModel();
              },
              autocorrect: false,
              enableSuggestions: false,
              enableIMEPersonalizedLearning: false,
              textCapitalization: TextCapitalization.none,
              maxLength: 100,
              decoration: const InputDecoration(
                labelText: 'Model ID',
                counterText: '',
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          itemHeight: null,
          key: ValueKey(thinking),
          initialValue: thinking,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Thinking'),
          items: [
            for (final level in CreatePreferences.thinkingLevels(
              model.text.trim(),
            ))
              DropdownMenuItem(
                value: level,
                child: Text(CreatePreferences.thinkingName(level)),
              ),
          ],
          onChanged: (value) => setState(() {
            useRecommended = false;
            thinking = value!;
          }),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              choice = models.containsKey(widget.recommendedModel)
                  ? widget.recommendedModel
                  : 'custom';
              model.text = widget.recommendedModel;
              thinking = widget.recommendedThinking;
              useRecommended = true;
              updateModel();
            },
            child: const Text('Reset to recommended'),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: model.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (
                model: model.text.trim(),
                thinking: thinking,
                useRecommended: useRecommended,
              )),
        child: const Text('Save'),
      ),
    ],
  );
}
