import 'page_headings.dart';
import 'pixel_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:material_symbols_icons/symbols.dart';

import '../app_platform.dart';
import '../create_preferences.dart';
import '../help_content.dart';
import '../settings_platform.dart';
import '../import_diagnostics.dart';
import '../import_service.dart';
import '../local_preferences.dart';
import '../src/rust/api.dart' show ProviderMode, ServiceError;
import 'components.dart';
import 'feedback.dart';
import 'gemini_model_dialog.dart';
import 'how_cookdex_works_screen.dart';
import 'navigation_feedback.dart';
import 'smart_record_dialog.dart';

Future<void> openSmartSettings(
  BuildContext context, {
  required ImportService service,
  required LocalPreferences preferences,
  Future<void> Function(String)? openUrl,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  cookdexRoute<void>(
    context,
    builder: (_) => SmartSettingsScreen(
      service: service,
      preferences: preferences,
      testKey: () => SettingsPlatform().testKey(service.platform),
      openUrl: openUrl ?? NativeAppPlatform().openSource,
    ),
  ),
);

Future<void> openGeminiKey(
  BuildContext context, {
  required ImportService service,
  Future<void> Function(String)? openUrl,
  Future<void> Function()? testKey,
}) => Navigator.of(context, rootNavigator: true).push<void>(
  cookdexRoute<void>(
    context,
    builder: (_) => SmartSettingsScreen(
      keyPage: true,
      service: service,
      testKey: testKey ?? () => SettingsPlatform().testKey(service.platform),
      openUrl: openUrl ?? NativeAppPlatform().openSource,
    ),
  ),
);

/// Key storage and explicit provider testing stay with the injected services.
class SmartSettingsScreen extends StatefulWidget {
  const SmartSettingsScreen({
    super.key,
    required this.service,
    this.keyPage = false,
    this.preferences,
    required this.testKey,
    required this.openUrl,
  });

  final bool keyPage;
  final LocalPreferences? preferences;
  final ImportService service;
  final Future<void> Function() testKey;
  final Future<void> Function(String) openUrl;

  @override
  State<SmartSettingsScreen> createState() => _SmartSettingsScreenState();
}

class _SmartSettingsScreenState extends State<SmartSettingsScreen> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  String _effort = 'standard';
  String _thinking = SmartImportSettings.recommendedThinking;
  SmartImportSettings? _saved;
  bool _busy = true;
  String? _error;

  bool get _unsaved =>
      _key.text.isNotEmpty ||
      _model.text != _saved?.model ||
      _effort != _saved?.effort;

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
      _effort = settings.effort;
      _thinking = settings.thinking;
    } catch (_) {
      if (mounted) {
        _error = widget.keyPage
            ? 'Could not load Gemini key settings.'
            : 'Could not load Smart Import settings.';
      }
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
        effort: _effort,
      );
      if (!mounted) return;
      // Clear immediately after the successful write, before refreshing state.
      _key.clear();
      final saved = await widget.service.platform.settings();
      if (!mounted) return;
      _saved = saved;
      _model.text = saved.model;
      _effort = saved.effort;
      _thinking = saved.thinking;
    },
    failure: widget.keyPage
        ? 'Could not save the Gemini key.'
        : 'Could not save Smart Import settings.',
    success: widget.keyPage
        ? 'Gemini key saved'
        : 'Smart Import settings saved',
  );

  Widget _saveButton() => FilledButton(
    onPressed:
        _busy ||
            _saved == null ||
            _model.text.trim().isEmpty ||
            (widget.keyPage && _key.text.trim().isEmpty)
        ? null
        : _save,
    child: const Text('Save'),
  );

  Future<void> _editModel() async {
    if (_busy || _saved == null) return;
    final result = await showDialog<GeminiModelSelection>(
      context: context,
      builder: (_) => GeminiModelDialog(
        title: 'Recipe import',
        model: _model.text,
        thinking: _thinking,
        recommendedModel: SmartImportSettings.recommendedModel,
        recommendedThinking: SmartImportSettings.recommendedThinking,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _model.text = result.model;
      _effort = result.thinking;
      _thinking = result.thinking;
    });
    await _save();
  }

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
      _saved = SmartImportSettings(
        hasKey: false,
        model: _saved!.model,
        effort: _saved!.effort,
      );
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
    await showLastSmartRecord(
      context,
      feature: 'Smart Import',
      record: record,
      clear: widget.service.clearAiDiagnostics,
    );
  }, failure: 'Could not read the last Smart Import.');

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: pageHeadingBar(
        context,
        title: widget.keyPage ? 'Gemini key' : 'Smart Import settings',
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
              if (!widget.keyPage)
                Card(
                  child: ListTile(
                    leading: const Icon(Symbols.key),
                    title: const Text('Gemini key'),
                    subtitle: Text(
                      _saved == null
                          ? 'Key status unavailable'
                          : _saved!.hasKey
                          ? 'Key saved on this device'
                          : 'No key saved',
                    ),
                    trailing: const Icon(Symbols.chevron_right),
                    enabled: !_busy,
                    onTap: () async {
                      await openGeminiKey(
                        context,
                        service: widget.service,
                        testKey: widget.testKey,
                        openUrl: widget.openUrl,
                      );
                      if (!mounted) return;
                      await _run(() async {
                        final saved = await widget.service.platform.settings();
                        if (mounted) _saved = saved;
                      }, failure: 'Could not read key status.');
                    },
                  ),
                ),
              if (widget.keyPage) ...[
                Text(
                  _saved?.hasKey == true
                      ? 'Key saved on this device'
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
              ],
              if (!widget.keyPage) ...[
                const SizedBox(height: 16),
                Text(
                  'Model and thinking',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Card(
                  child: ListTile(
                    title: const Text('Recipe import'),
                    subtitle: _saved == null
                        ? null
                        : Text(
                            '${CreatePreferences.modelName(_model.text)} · ${CreatePreferences.thinkingName(_thinking)}',
                          ),
                    trailing: const Icon(Symbols.edit),
                    enabled: !_busy && _saved != null,
                    onTap: _busy || _saved == null ? null : _editModel,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (!widget.keyPage)
                Text(
                  'Watching YouTube videos uses Gemini 3.8 Flash. '
                  'This setting does not change it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (widget.keyPage) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _saveButton(),
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
                      onPressed: _busy || _saved?.hasKey != true
                          ? null
                          : _remove,
                      child: const Text('Remove key'),
                    ),
                  ],
                ),
              ],
              if (_saved != null && _error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              if (widget.keyPage) ...[
                const Text(
                  'When you use Smart Import or Smart Create, Google receives what you send, like a link, text or the photos you pick, plus your library’s tag names.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).push<void>(
                            cookdexRoute<void>(
                              context,
                              builder: (_) => HowCookdexWorksScreen(
                                openDataSection: true,
                                loadAppInfo: SettingsPlatform().appInfo,
                                openUrl: widget.openUrl,
                              ),
                            ),
                          ),
                      icon: const Icon(Symbols.help_outline),
                      label: const Text(dataHelpTitle),
                    ),
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
              ],
              if (!widget.keyPage)
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
