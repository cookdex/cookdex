import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../create_preferences.dart';
import '../import_service.dart';
import '../local_preferences.dart';
import '../smart_create_protocol.dart'
    show photoPrompt, ideaPrompt, moodIdeaPrompt, recipePrompt;
import 'gemini_model_dialog.dart';
import 'navigation_feedback.dart';
import 'page_headings.dart';
import 'pixel_scroll.dart';
import 'smart_create_controls.dart';
import 'smart_record_dialog.dart';
import 'smart_settings_screen.dart';

Future<void> openCreateSettings(
  BuildContext context, {
  required LocalPreferences preferences,
  required ImportService service,
  required Future<void> Function(BuildContext) onStaples,
  required Future<String?> Function() lastDiagnostic,
  required Future<void> Function() clearDiagnostic,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  cookdexRoute<void>(
    context,
    builder: (_) => CreateSettingsScreen(
      preferences: preferences,
      service: service,
      onStaples: onStaples,
      lastDiagnostic: lastDiagnostic,
      clearDiagnostic: clearDiagnostic,
    ),
  ),
);

Future<void> _editNames(
  BuildContext context, {
  required LocalPreferences preferences,
  required bool staples,
}) async {
  final result = await showDialog<List<String>>(
    context: context,
    builder: (_) => _NamesDialog(
      staples: staples,
      initial: staples
          ? preferences.createPreferences.staples
          : preferences.createPreferences.avoid,
    ),
  );
  if (result == null) return;
  final latest = preferences.createPreferences;
  preferences.setCreatePreferences(
    staples ? latest.copyWith(staples: result) : latest.copyWith(avoid: result),
  );
}

class _NamesDialog extends StatefulWidget {
  const _NamesDialog({required this.initial, required this.staples});
  final List<String> initial;
  final bool staples;
  @override
  State<_NamesDialog> createState() => _NamesDialogState();
}

class _NamesDialogState extends State<_NamesDialog> {
  final input = TextEditingController();
  late final names = List.of(widget.initial);

  void add() {
    final value = input.text.trim();
    if (value.isEmpty) return;
    setState(() {
      if (!names.any((n) => n.toLowerCase() == value.toLowerCase())) {
        names.add(value);
      }
      input.clear();
    });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.staples ? 'Staples' : 'Foods to avoid'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.staples)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Always check the ingredients yourself for allergies.'),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final name in names)
              InputChip(
                label: Text(name),
                onDeleted: () => setState(() => names.remove(name)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: input,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => add(),
          decoration: InputDecoration(
            labelText: 'Add ingredient',
            suffixIcon: IconButton(
              tooltip: 'Add ingredient',
              icon: const Icon(Symbols.add),
              onPressed: add,
            ),
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
        onPressed: () {
          add();
          Navigator.pop(context, names);
        },
        child: const Text('Save'),
      ),
    ],
  );
}

class CreateSettingsScreen extends StatefulWidget {
  const CreateSettingsScreen({
    super.key,
    required this.preferences,
    required this.service,
    required this.onStaples,
    required this.lastDiagnostic,
    required this.clearDiagnostic,
  });
  final LocalPreferences preferences;
  final ImportService service;
  final Future<void> Function(BuildContext) onStaples;
  final Future<String?> Function() lastDiagnostic;
  final Future<void> Function() clearDiagnostic;
  @override
  State<CreateSettingsScreen> createState() => _CreateSettingsScreenState();
}

class _CreateSettingsScreenState extends State<CreateSettingsScreen> {
  bool _readingDiagnostic = false;
  late Future<SmartImportSettings> keyStatus = widget.service.platform
      .settings();

  Future<void> _showText(String title, List<(String, String)> entries) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final entry in entries) ...[
                if (entry.$1.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      entry.$1,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                SelectableText(entry.$2),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

  Future<void> _diagnostic() async {
    if (_readingDiagnostic) return;
    setState(() => _readingDiagnostic = true);
    final String? record;
    try {
      record = await widget.lastDiagnostic();
    } catch (_) {
      if (mounted && ModalRoute.isCurrentOf(context) == true) {
        await _showText('Last Smart Create', [
          ('', 'Could not read the last Smart Create.'),
        ]);
      }
      return;
    } finally {
      if (mounted) setState(() => _readingDiagnostic = false);
    }
    if (!mounted || ModalRoute.isCurrentOf(context) != true) return;
    await showLastSmartRecord(
      context,
      feature: 'Smart Create',
      record: record,
      clear: widget.clearDiagnostic,
    );
  }

  Future<void> _editCount({required bool extra}) async {
    final p = widget.preferences.createPreferences;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => _CountDialog(
        title: extra ? 'Items to buy per idea' : 'Default servings',
        noun: extra ? 'items' : 'servings',
        description: extra
            ? "The most ingredients you don't have that a Need a few things idea "
                  "can call for. Staples don't count. Doesn't apply when you only "
                  'type a mood.'
            : null,
        current: extra ? p.extraIngredients : p.servings,
        maximum: extra ? 6 : 99,
      ),
    );
    if (!mounted || result == null) return;
    widget.preferences.setCreatePreferences(
      extra
          ? widget.preferences.createPreferences.copyWith(
              extraIngredients: result,
            )
          : widget.preferences.createPreferences.copyWith(servings: result),
    );
  }

  Future<void> _editOtherPreferences() async {
    var text = widget.preferences.createPreferences.otherPreferences;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Other preferences'),
        content: Semantics(
          label: 'Other preferences',
          child: TextFormField(
            initialValue: text,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (value) => text = value,
            decoration: const InputDecoration(
              hintText:
                  'e.g. no egg-heavy dishes like omelettes or German pancakes',
              hintMaxLines: 5,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || result == null) return;
    widget.preferences.setCreatePreferences(
      widget.preferences.createPreferences.copyWith(otherPreferences: result),
    );
  }

  Future<void> _model(CreateStep step) async {
    final p = widget.preferences.createPreferences;
    final result = await showDialog<GeminiModelSelection>(
      context: context,
      builder: (_) => GeminiModelDialog(
        title: step.label,
        model: p.modelFor(step),
        thinking: p.thinkingFor(step),
        recommendedModel: CreatePreferences.suggestedModel,
        recommendedThinking: CreatePreferences.suggestedThinking,
        useRecommended: p.usesRecommendedFor(step),
      ),
    );
    if (!mounted || result == null) return;
    widget.preferences.setCreatePreferences(
      widget.preferences.createPreferences.withSelection(
        step,
        result.model,
        result.thinking,
        useRecommended: result.useRecommended,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: pageHeadingBar(context, title: 'Smart Create settings'),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: widget.preferences,
        builder: (context, _) {
          final p = widget.preferences.createPreferences;
          return PixelSingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: FutureBuilder<SmartImportSettings>(
                    future: keyStatus,
                    builder: (_, state) => ListTile(
                      leading: const Icon(Symbols.key),
                      title: const Text('Gemini key'),
                      subtitle: Text(
                        state.hasData
                            ? state.data!.hasKey
                                  ? 'Key saved on this device'
                                  : 'No key saved'
                            : state.hasError
                            ? 'Key status unavailable'
                            : 'Checking key status…',
                      ),
                      trailing: const Icon(Symbols.chevron_right),
                      onTap: () async {
                        await openGeminiKey(context, service: widget.service);
                        if (mounted) {
                          setState(
                            () =>
                                keyStatus = widget.service.platform.settings(),
                          );
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      for (final staples in [true, false])
                        ListTile(
                          title: Text(staples ? 'Staples' : 'Foods to avoid'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if ((staples ? p.staples : p.avoid).isEmpty)
                                const Text('None'),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final name
                                      in staples ? p.staples : p.avoid)
                                    Chip(label: Text(name)),
                                ],
                              ),
                              if (!staples)
                                const Text(
                                  'Always check the ingredients yourself for allergies.',
                                ),
                            ],
                          ),
                          trailing: Icon(
                            staples ? Symbols.chevron_right : Symbols.edit,
                          ),
                          onTap: () => staples
                              ? widget.onStaples(context)
                              : _editNames(
                                  context,
                                  preferences: widget.preferences,
                                  staples: false,
                                ),
                        ),
                      ListTile(
                        title: const Text('Other preferences'),
                        subtitle: Text(
                          p.otherPreferences.isEmpty
                              ? 'None'
                              : p.otherPreferences,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Symbols.edit),
                        onTap: _editOtherPreferences,
                      ),
                      ListTile(
                        title: const Text('Default servings'),
                        subtitle: Text('${p.servings}'),
                        trailing: const Icon(Symbols.edit),
                        onTap: () => _editCount(extra: false),
                      ),
                      ListTile(
                        title: const Text('Items to buy per idea'),
                        subtitle: Text('Up to ${p.extraIngredients}'),
                        trailing: const Icon(Symbols.edit),
                        onTap: () => _editCount(extra: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Model and thinking',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Card(
                  child: Column(
                    children: [
                      for (final step in CreateStep.values)
                        ListTile(
                          title: Text(step.label),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${CreatePreferences.modelName(p.modelFor(step))} · ${CreatePreferences.thinkingName(p.thinkingFor(step))}',
                              ),
                              if (p.retiredModelFor(step)
                                  case final String retired)
                                Text(
                                  '${CreatePreferences.modelName(retired)} is no longer available. Switched to ${CreatePreferences.modelName(CreatePreferences.suggestedModel)}.',
                                ),
                            ],
                          ),
                          trailing: const Icon(Symbols.edit),
                          onTap: () => _model(step),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Symbols.description),
                        title: const Text('View prompts'),
                        onTap: () => _showText('View prompts', const [
                          ('Photo recognition', photoPrompt),
                          ('Recipe ideas — ingredients or photos', ideaPrompt),
                          ('Recipe ideas — mood only', moodIdeaPrompt),
                          ('Full recipe', recipePrompt),
                        ]),
                      ),
                      ListTile(
                        leading: const Icon(Symbols.history),
                        title: const Text('Last Smart Create'),
                        onTap: _readingDiagnostic ? null : _diagnostic,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _CountDialog extends StatefulWidget {
  const _CountDialog({
    required this.title,
    required this.noun,
    this.description,
    required this.current,
    required this.maximum,
  });
  final String title, noun;
  final String? description;
  final int current, maximum;
  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  late int count = widget.current;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
    title: Text(widget.title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CreateCountStepper(
          value: count,
          maximum: widget.maximum,
          noun: widget.noun,
          onChanged: (value) => setState(() => count = value),
        ),
        if (widget.description case final String description) ...[
          const SizedBox(height: 16),
          Text(description),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, count),
        child: const Text('Save'),
      ),
    ],
  );
}
