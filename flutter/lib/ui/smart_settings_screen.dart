import 'page_headings.dart';
import 'pixel_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:material_symbols_icons/symbols.dart';

import '../app_platform.dart';
import '../help_content.dart';
import '../settings_platform.dart';
import '../import_diagnostics.dart';
import '../import_service.dart';
import '../local_preferences.dart';
import '../src/rust/api.dart' show ProviderMode, ServiceError;
import 'components.dart';
import 'feedback.dart';
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
  static const _recommendedModel = 'gemini-3.5-flash-lite';
  final _key = TextEditingController();
  final _model = TextEditingController();
  String _effort = 'standard';
  late YoutubeWatchModel _watchModel;
  bool _customModel = false;
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
    _watchModel =
        widget.preferences?.youtubeWatchModel ?? YoutubeWatchModel.flash;
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
      _customModel = settings.model != _recommendedModel;
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
      final prefs = widget.preferences;
      if (!widget.keyPage && prefs != null) {
        prefs.setYoutubeWatchModel(_watchModel);
        await prefs.flush();
        if (!mounted) return;
        if (prefs.persistenceError != null) {
          throw StateError(prefs.persistenceError!);
        }
      }
      // Clear immediately after the successful write, before refreshing state.
      _key.clear();
      final saved = await widget.service.platform.settings();
      if (!mounted) return;
      _saved = saved;
      _model.text = saved.model;
      _effort = saved.effort;
      _customModel = saved.model != _recommendedModel;
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
              if (!widget.keyPage)
                ExpansionTile(
                  title: const Text('Advanced'),
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 8, bottom: 16),
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey('effort-$_effort'),
                      initialValue: _effort,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Effort'),
                      items: const [
                        DropdownMenuItem(
                          value: 'standard',
                          child: Text('Standard'),
                        ),
                        DropdownMenuItem(
                          value: 'thorough',
                          child: Text('Thorough'),
                        ),
                      ],
                      onChanged: _busy || _saved == null
                          ? null
                          : (value) => setState(() => _effort = value!),
                    ),
                    const SizedBox(height: 8),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Thorough is slower and uses more of your free daily limit.',
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<bool>(
                      key: ValueKey('model-$_customModel'),
                      initialValue: _customModel,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Model'),
                      items: const [
                        DropdownMenuItem(
                          value: false,
                          child: Text('Gemini 3.5 Flash-Lite (recommended)'),
                        ),
                        DropdownMenuItem(
                          value: true,
                          child: Text('Custom model ID'),
                        ),
                      ],
                      onChanged: _busy || _saved == null
                          ? null
                          : (value) => setState(() {
                              _customModel = value!;
                              _model.text = _customModel
                                  ? ''
                                  : _recommendedModel;
                            }),
                    ),
                    SizedBox(height: _customModel ? 16 : 8),
                    if (_customModel)
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
                            labelText: 'Custom model ID',
                            counterText: '',
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<YoutubeWatchModel>(
                      key: ValueKey('youtube-${_watchModel.name}'),
                      initialValue: _watchModel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'YouTube watching model',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: YoutubeWatchModel.flash,
                          child: Text('Gemini 3.8 Flash'),
                        ),
                        DropdownMenuItem(
                          value: YoutubeWatchModel.followImport,
                          child: Text('Follow Smart Import'),
                        ),
                        DropdownMenuItem(
                          value: YoutubeWatchModel.lite,
                          child: Text('Gemini 3.5 Flash-Lite'),
                        ),
                      ],
                      onChanged: _busy || _saved == null
                          ? null
                          : (value) => setState(() => _watchModel = value!),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy || _saved == null
                            ? null
                            : () => setState(() {
                                _effort = 'standard';
                                _customModel = false;
                                _model.text = _recommendedModel;
                                _watchModel = YoutubeWatchModel.flash;
                              }),
                        child: const Text('Reset to recommended'),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _saveButton(),
                    ),
                  ],
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
