import 'pixel_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:material_symbols_icons/symbols.dart';

import '../import_diagnostics.dart';
import '../import_service.dart';
import '../src/rust/api.dart' show ProviderMode, ServiceError;
import 'components.dart';
import 'feedback.dart';

/// Key storage and explicit provider testing stay with the injected services.
class SmartSettingsScreen extends StatefulWidget {
  const SmartSettingsScreen({
    super.key,
    required this.service,
    required this.testKey,
    required this.openUrl,
  });

  final ImportService service;
  final Future<void> Function() testKey;
  final Future<void> Function(String) openUrl;

  @override
  State<SmartSettingsScreen> createState() => _SmartSettingsScreenState();
}

class _SmartSettingsScreenState extends State<SmartSettingsScreen> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  SmartImportSettings? _saved;
  bool _busy = true;
  String? _error;

  bool get _unsaved => _key.text.isNotEmpty || _model.text != _saved?.model;

  @override
  void initState() {
    super.initState();
    _key.addListener(_changed);
    _model.addListener(_changed);
    _load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await widget.service.platform.settings();
      if (!mounted) return;
      _saved = settings;
      _model.text = settings.model;
    } catch (_) {
      if (mounted) _error = 'Could not load Smart Import settings.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String failure,
    String? success,
    bool providerError = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && success != null) showFeedback(context, success);
    } catch (error) {
      if (!mounted) return;
      var reason = providerError
          ? switch (error) {
              ServiceError(:final message) => message,
              StateError(:final message) => message.toString(),
              PlatformException(:final message) => message ?? failure,
              _ => failure,
            }
          : failure;
      // Never echo an entered key if an injected provider error contains it.
      if (_key.text.isNotEmpty) {
        reason = reason.replaceAll(_key.text, '[redacted key]');
      }
      _error = redactImportDiagnostic(reason, limit: 500);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(
    () async {
      await widget.service.platform.saveSettings(
        key: _key.text.trim(),
        model: _model.text.trim(),
      );
      if (!mounted) return;
      // Clear immediately after the successful write, before refreshing state.
      _key.clear();
      final saved = await widget.service.platform.settings();
      if (!mounted) return;
      _saved = saved;
      _model.text = saved.model;
    },
    failure: 'Could not save Smart Import settings.',
    success: 'Smart Import settings saved',
  );

  Future<void> _remove() async {
    if (_busy || _saved?.hasKey != true) return;
    if (!await confirmCookdex(
      context,
      title: 'Remove the Gemini key from this device?',
      action: 'Remove key',
      destructive: true,
    )) {
      return;
    }
    if (!mounted) return;
    await _run(() async {
      await widget.service.platform.removeKey();
      if (!mounted) return;
      _key.clear();
      _saved = SmartImportSettings(hasKey: false, model: _saved!.model);
    }, failure: 'Could not remove the key.');
  }

  Future<void> _viewPrompts() => _run(() async {
    final prompts = await Future.wait([
      widget.service.jsonPrompt(),
      widget.service.jsonPrompt(mode: ProviderMode.urlRecipe),
      widget.service.jsonPrompt(photos: true),
      widget.service.prompt(),
    ]);
    if (!mounted) return;
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('View prompts'),
        content: SizedBox(
          width: 640,
          child: PixelSingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < prompts.length; i++) ...[
                  if (i > 0) const SizedBox(height: 24),
                  Text(
                    const [
                      'In-app JSON prompt (Text)',
                      'In-app JSON prompt (Link)',
                      'In-app JSON prompt (Photos)',
                      'Copy Text v1 prompt',
                    ][i],
                    style: Theme.of(dialogContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(prompts[i]),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }, failure: 'Could not load the AI prompts.');

  Future<void> _viewDiagnostic() => _run(() async {
    final record = await widget.service.lastAiDiagnostics();
    if (!mounted) return;
    setState(() => _busy = false);
    var clearing = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => PopScope(
          canPop: !clearing,
          child: AlertDialog(
            title: const Text('Last Smart Import'),
            content: SizedBox(
              width: 640,
              child: PixelSingleChildScrollView(
                child: SelectableText(
                  record == null
                      ? 'No Smart Import has been recorded.'
                      : redactImportDiagnostic(record),
                ),
              ),
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
                          update(() => clearing = true);
                          try {
                            await widget.service.clearAiDiagnostics();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (_) {
                            if (!dialogContext.mounted) return;
                            update(() => clearing = false);
                            showFeedback(
                              dialogContext,
                              'Could not clear the last Smart Import.',
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
  }, failure: 'Could not read the last Smart Import.');

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Smart Import settings'),
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back),
          tooltip: 'Back',
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: PixelSingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_saved == null && _error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_saved == null && !_busy)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _load,
                    child: const Text('Retry'),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _saved?.hasKey == true
                    ? 'Key saved. Leave blank to keep it.'
                    : 'No key saved',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              PixelScrollScope(
                axis: Axis.horizontal,
                builder: (context) => TextField(
                  scrollController: PrimaryScrollController.of(context),
                  controller: _key,
                  enabled: !_busy && _saved != null,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  textCapitalization: TextCapitalization.none,
                  maxLength: 256,
                  decoration: const InputDecoration(
                    labelText: 'Gemini key',
                    hintText: 'Add or replace key',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              PixelScrollScope(
                axis: Axis.horizontal,
                builder: (context) => TextField(
                  scrollController: PrimaryScrollController.of(context),
                  controller: _model,
                  enabled: !_busy && _saved != null,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  textCapitalization: TextCapitalization.none,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed:
                        _busy || _saved == null || _model.text.trim().isEmpty
                        ? null
                        : _save,
                    child: const Text('Save'),
                  ),
                  OutlinedButton(
                    onPressed: _busy || _saved?.hasKey != true || _unsaved
                        ? null
                        : () => _run(
                            widget.testKey,
                            failure: 'Could not test the Gemini key.',
                            success: 'Gemini key works',
                            providerError: true,
                          ),
                    child: const Text('Test key'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _busy || _saved?.hasKey != true ? null : _remove,
                    child: const Text('Remove key'),
                  ),
                ],
              ),
              if (_saved != null && _error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'AI imports send selected inputs to Google. Keys stay on this device.',
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.openUrl(
                              'https://aistudio.google.com/apikey',
                            ),
                            failure: 'Could not open Google AI Studio.',
                          ),
                    icon: const Icon(Symbols.open_in_new),
                    label: const Text('Get a Gemini key'),
                  ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => widget.openUrl(
                              'https://ai.google.dev/gemini-api/docs/pricing',
                            ),
                            failure: 'Could not open pricing and data use.',
                          ),
                    icon: const Icon(Symbols.open_in_new),
                    label: const Text('Pricing and data use'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Symbols.description),
                      title: const Text('View prompts'),
                      minVerticalPadding: 12,
                      enabled: !_busy,
                      onTap: _busy ? null : _viewPrompts,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Symbols.history),
                      title: const Text('Last Smart Import'),
                      minVerticalPadding: 12,
                      enabled: !_busy,
                      onTap: _busy ? null : _viewDiagnostic,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
