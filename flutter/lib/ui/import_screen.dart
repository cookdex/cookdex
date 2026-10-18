import 'pixel_scroll.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../import_controller.dart';
import '../import_service.dart';
import '../src/rust/api.dart' as core;
import 'components.dart';
import 'feedback.dart';
import 'navigation_feedback.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.controller,
    required this.onReview,
    this.onTextReview,
    this.onTextBatch,
    this.initialInput,
  });
  final ImportController controller;
  final Future<core.Recipe?> Function(BuildContext, core.Candidate)?
  onTextReview;
  final Future<core.Recipe?> Function(BuildContext, List<TextImportBlock>)?
  onTextBatch;
  final Future<void> Function(ImportController)? initialInput;
  final Future<core.Recipe?> Function(BuildContext, core.Candidate) onReview;
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen>
    with WidgetsBindingObserver {
  ImportController get c => widget.controller;
  final _text = TextEditingController(), _link = TextEditingController();
  bool _leaving = false, _backPending = false;
  bool _backCancelled = false, _finishing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    await c.load();
    if (widget.initialInput != null) await widget.initialInput!(c);
    if (!mounted) return;
    _syncFields();
    if (widget.initialInput != null && isCookdexText(c.text)) await _import();
  }

  void _syncFields() {
    _text.text = c.text;
    _link.text = c.link;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(c.flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _link.dispose();
    super.dispose();
  }

  void _cancelForBack() {
    if (_backCancelled) return;
    _backCancelled = true;
    c.cancel();
  }

  Future<void> _back() async {
    if (_backPending || _leaving || _finishing) return;
    _backPending = true;
    _cancelForBack();
    await c.flush();
    if (!mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _import({bool? useAi}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final discovery = await c.discover(useAi: useAi);
    if (!mounted || discovery == null) return;
    if (discovery.textBlocks.isNotEmpty &&
        (discovery.textBlocks.length > 1 ||
            discovery.textBlocks.single.candidate == null)) {
      final saved = await widget.onTextBatch?.call(
        context,
        discovery.textBlocks,
      );
      if (saved != null && mounted) await _finish(saved);
      return;
    }
    if (discovery.canTryWithAi && discovery.candidates.isNotEmpty) {
      final tryAi = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Embedded recipe needs review'),
          content: Text(discovery.warnings.join('\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Review embedded recipe'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Try with AI'),
            ),
          ],
        ),
      );
      if (!mounted || tryAi == null) return;
      if (tryAi) {
        await _import(useAi: true);
        return;
      }
    }
    if (discovery.candidates.isEmpty) {
      c.error = discovery.warnings.isEmpty
          ? 'No recipe found.'
          : discovery.warnings.join('\n');
      c.changed(clearError: false);
      return;
    }
    final int? index;
    if (discovery.candidates.length == 1) {
      index = 0;
    } else {
      index = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Choose one recipe'),
          content: SizedBox(
            width: 420,
            child: PixelListView.builder(
              shrinkWrap: true,
              itemCount: discovery.candidates.length,
              itemBuilder: (context, index) {
                final recipe = discovery.candidates[index].recipe;
                return ListTile(
                  title: Text(recipe.fields.title),
                  subtitle: recipe.fields.description.isEmpty
                      ? null
                      : Text(
                          recipe.fields.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => Navigator.pop(context, index),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
    if (!mounted || index == null) return;
    final candidate = await c.select(discovery, index);
    if (!mounted || candidate == null) return;
    final reviewed = core.Candidate(
      recipe: candidate.recipe,
      warnings: {...discovery.warnings, ...candidate.warnings}.toList(),
      ingredientSources: candidate.ingredientSources,
      aiReview: candidate.aiReview,
    );
    final review = discovery.textBlocks.isNotEmpty
        ? widget.onTextReview ?? widget.onReview
        : widget.onReview;
    final saved = await review(context, reviewed);
    if (!mounted || saved == null) return;
    await _finish(saved);
  }

  Future<void> _finish(core.Recipe saved) async {
    _finishing = true;
    final photoWarning = await c.saveOriginalsAfterRecipe(saved.fields.title);
    if (photoWarning != null && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recipe saved'),
          content: Text(photoWarning),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    try {
      await c.clear();
    } catch (_) {
      /* Recipe is already committed. */
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  Future<void> _clear() async {
    if (!await confirmCookdex(
      context,
      title: 'Clear Smart Import?',
      action: 'Clear',
      destructive: true,
    )) {
      return;
    }
    try {
      await c.clear();
      _syncFields();
    } catch (_) {
      c.error = 'Could not clear the import draft.';
      c.changed(clearError: false);
    }
  }

  Future<void> _viewPrompt() async {
    try {
      final json = await c.service.jsonPrompt(
        mode: c.tab == ImportTab.link
            ? core.ProviderMode.urlRecipe
            : core.ProviderMode.recipe,
        photos: c.tab == ImportTab.photos,
      );
      final text = await c.service.prompt();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('View prompt'),
          content: SizedBox(
            width: 640,
            child: PixelSingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'In-app JSON prompt (${c.tab.name})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(json),
                  const SizedBox(height: 24),
                  Text(
                    'Copy Text v1 prompt',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  SelectableText(text),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      c.error = 'Could not load the AI prompts.';
      c.changed(clearError: false);
    }
  }

  Future<void> _viewLastAiImport() async {
    try {
      final diagnostic = await c.service.lastAiDiagnostics();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Last Smart Import'),
          content: SizedBox(
            width: 640,
            child: PixelSingleChildScrollView(
              child: SelectableText(
                diagnostic ?? 'No Smart Import has been recorded.',
              ),
            ),
          ),
          actions: [
            if (diagnostic != null)
              TextButton(
                onPressed: () async {
                  try {
                    await c.service.clearAiDiagnostics();
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (context.mounted) {
                      showFeedback(
                        context,
                        'Could not clear the last Smart Import.',
                        kind: FeedbackKind.error,
                      );
                    }
                  }
                },
                child: const Text('Clear record'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      c.error = 'Could not read the last Smart Import.';
      c.changed(clearError: false);
    }
  }

  Future<void> _settings() async {
    final settings = await c.run(c.service.platform.settings);
    if (!mounted || settings == null) return;
    final key = TextEditingController(),
        model = TextEditingController(text: settings.model);
    String? error;
    bool saving = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('Smart Import settings'),
            content: PixelSingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PixelScrollScope(
                    axis: Axis.horizontal,
                    builder: (context) => TextField(
                      scrollController: PrimaryScrollController.of(context),
                      controller: key,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Gemini key',
                        hintText: settings.hasKey ? 'Key saved' : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  PixelScrollScope(
                    axis: Axis.horizontal,
                    builder: (context) => TextField(
                      scrollController: PrimaryScrollController.of(context),
                      controller: model,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Model'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Smart Import sends recipes to Google.'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: saving ? null : _viewPrompt,
                        child: const Text('View prompt'),
                      ),
                      TextButton(
                        onPressed: saving ? null : _viewLastAiImport,
                        child: const Text('Last Smart Import'),
                      ),
                    ],
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (settings.hasKey)
                TextButton(
                  onPressed: saving
                      ? null
                      : () async {
                          setDialogState(() => saving = true);
                          try {
                            await c.service.platform.removeKey();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          } catch (_) {
                            if (!dialogContext.mounted) return;
                            setDialogState(() {
                              saving = false;
                              error = 'Could not remove the key.';
                            });
                          }
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Remove key'),
                ),
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        try {
                          await c.service.platform.saveSettings(
                            key: key.text,
                            model: model.text,
                          );
                          if (dialogContext.mounted) {
                            key.clear();
                            Navigator.pop(dialogContext);
                          }
                        } catch (_) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              saving = false;
                              error = 'Could not save Smart Import settings.';
                            });
                          }
                        }
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    // Dialog route finishes animating after its result completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    key.dispose();
    model.dispose();
  }

  Axis _importTabDirection(BuildContext context, double width) {
    final theme = Theme.of(context);
    final style = SegmentedButtonTheme.of(context).style;
    final textStyle =
        style?.textStyle?.resolve(const {}) ?? theme.textTheme.labelLarge!;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    var widestLabel = 0.0;
    for (final label in const ['Text', 'Link', 'Photos']) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > widestLabel) widestLabel = painter.width;
      painter.dispose();
    }
    // Reserve the selected checkmark for every segment, so changing selection
    // never wraps a label or changes the orientation. Match Material's scaled
    // selected-segment padding and icon gap.
    final scale = scaler.scale(textStyle.fontSize ?? 14) / 14;
    final padding = ButtonStyleButton.scaledPadding(
      const EdgeInsetsDirectional.fromSTEB(12, 8, 16, 8),
      const EdgeInsets.symmetric(horizontal: 4),
      const EdgeInsets.symmetric(horizontal: 4),
      scale,
    ).resolve(direction);
    final icon = style?.iconSize?.resolve(const {}) ?? 18;
    final gap = 8 - 4 * (scale.clamp(1.0, 2.0) - 1);
    return 3 * (widestLabel + padding.horizontal + icon + gap) <= width
        ? Axis.horizontal
        : Axis.vertical;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => PredictiveFormBackGuard(
      enabled: !_leaving && !_backPending,
      onBack: _back,
      onCommit: _cancelForBack,
      child: PopScope(
        canPop: _leaving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_back());
        },
        child: CookdexFormScaffold(
          title: 'Smart Import',
          child: !c.loaded
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: PixelListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) =>
                              SegmentedButton<ImportTab>(
                                direction: _importTabDirection(
                                  context,
                                  constraints.maxWidth,
                                ),
                                segments: const [
                                  ButtonSegment(
                                    value: ImportTab.text,
                                    label: Text('Text'),
                                  ),
                                  ButtonSegment(
                                    value: ImportTab.link,
                                    label: Text('Link'),
                                  ),
                                  ButtonSegment(
                                    value: ImportTab.photos,
                                    label: Text('Photos'),
                                  ),
                                ],
                                selected: {c.tab},
                                onSelectionChanged: c.busy
                                    ? null
                                    : (values) {
                                        c.tab = values.single;
                                        c.changed();
                                      },
                              ),
                        ),
                        const SizedBox(height: 16),
                        if (c.tab == ImportTab.text) ...[
                          PixelScrollScope(
                            axis: Axis.horizontal,
                            builder: (context) => TextField(
                              scrollController: PrimaryScrollController.of(
                                context,
                              ),
                              controller: _text,
                              enabled: !c.busy,
                              minLines: 8,
                              maxLines: 16,
                              decoration: const InputDecoration(
                                hintText: 'Paste recipe text',
                              ),
                              onChanged: (value) {
                                c.text = value;
                                c.changed();
                              },
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: c.busy
                                  ? null
                                  : () async {
                                      await c.pickText();
                                      _syncFields();
                                    },
                              icon: const Icon(Symbols.file_open),
                              label: const Text('Open .txt file'),
                            ),
                          ),
                        ],
                        if (c.tab == ImportTab.link) ...[
                          PixelScrollScope(
                            axis: Axis.horizontal,
                            builder: (context) => TextField(
                              scrollController: PrimaryScrollController.of(
                                context,
                              ),
                              controller: _link,
                              enabled: !c.busy,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                hintText: 'Recipe link',
                              ),
                              onChanged: (value) {
                                c.link = value;
                                c.changed();
                              },
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: c.useAiForLink,
                            onChanged: c.busy
                                ? null
                                : (value) => c.setUseAiForLink(value ?? false),
                            title: const Text('Use AI for this link'),
                          ),
                        ],
                        if (c.tab == ImportTab.photos) ...[
                          if (c.photos.isNotEmpty)
                            SizedBox(
                              height: 208,
                              child: PixelScrollScope(
                                axis: Axis.horizontal,
                                builder: (context) => ReorderableListView.builder(
                                  scrollController: PrimaryScrollController.of(
                                    context,
                                  ),
                                  scrollDirection: Axis.horizontal,
                                  buildDefaultDragHandles: false,
                                  itemCount: c.photos.length,
                                  onReorderItem: (oldIndex, newIndex) {
                                    if (c.busy) return;
                                    final photo = c.photos.removeAt(oldIndex);
                                    c.photos.insert(newIndex, photo);
                                    c.changed();
                                  },
                                  itemBuilder: (context, index) {
                                    final photo = c.photos[index];
                                    return Padding(
                                      key: ValueKey(photo.id),
                                      padding: const EdgeInsets.only(right: 12),
                                      child: SizedBox(
                                        width: 160,
                                        child: Column(
                                          children: [
                                            SizedBox.square(
                                              dimension: 160,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.memory(
                                                      photo.jpeg,
                                                      fit: BoxFit.cover,
                                                      semanticLabel:
                                                          'Photo ${index + 1}',
                                                      errorBuilder: (_, _, _) =>
                                                          ColoredBox(
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .surfaceContainer,
                                                            child: const Icon(
                                                              Symbols.image,
                                                            ),
                                                          ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    top: 4,
                                                    right: 4,
                                                    child: IconButton.filledTonal(
                                                      tooltip:
                                                          'Remove photo ${index + 1}',
                                                      onPressed: c.busy
                                                          ? null
                                                          : () {
                                                              c.removePhoto(
                                                                index,
                                                              );
                                                              c.changed();
                                                            },
                                                      style: IconButton.styleFrom(
                                                        minimumSize:
                                                            const Size.square(
                                                              48,
                                                            ),
                                                        backgroundColor:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .errorContainer,
                                                        foregroundColor:
                                                            Theme.of(context)
                                                                .colorScheme
                                                                .onErrorContainer,
                                                      ),
                                                      icon: const Icon(
                                                        Symbols.delete,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            ReorderableDragStartListener(
                                              index: index,
                                              enabled: !c.busy,
                                              child: SizedBox(
                                                height: 48,
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      '${index + 1}',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Icon(
                                                      Symbols.drag_handle,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 24,
                            runSpacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: c.busy || c.photos.length == 8
                                    ? null
                                    : () => c.addPhotos(camera: true),
                                icon: const Icon(Symbols.photo_camera),
                                label: const Text('Camera'),
                              ),
                              TextButton.icon(
                                onPressed: c.busy || c.photos.length == 8
                                    ? null
                                    : () => c.addPhotos(camera: false),
                                icon: const Icon(Symbols.photo_library),
                                label: const Text('Gallery'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (c.photoSavingAvailable)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('Save photos to device'),
                              subtitle: const Text(
                                'Camera and gallery photos are copied to the cookdex album when you save the recipe.',
                              ),
                              value: c.savePhotosToDevice,
                              onChanged: c.busy
                                  ? null
                                  : (value) => c.setSavePhotosToDevice(value!),
                            ),
                          Text(
                            '${c.photos.length} of 8',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                        for (final warning in c.warnings)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(warning),
                          ),
                        if (c.error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              c.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        if (c.canTryWithAi && !c.busy)
                          OutlinedButton(
                            onPressed: () => _import(useAi: true),
                            child: const Text('Try with AI'),
                          ),
                        if (c.busy) ...[
                          const LinearProgressIndicator(),
                          TextButton(
                            onPressed: c.cancel,
                            child: const Text('Cancel'),
                          ),
                        ] else
                          FilledButton(
                            onPressed: _import,
                            child: const Text('Smart Import'),
                          ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: c.busy
                                  ? null
                                  : () async {
                                      try {
                                        final prompt = await c.service.prompt();
                                        await Clipboard.setData(
                                          ClipboardData(text: prompt),
                                        );
                                        if (context.mounted) {
                                          showFeedback(
                                            context,
                                            'AI prompt copied',
                                          );
                                        }
                                      } catch (_) {
                                        c.error =
                                            'Could not copy the AI prompt.';
                                        c.changed(clearError: false);
                                      }
                                    },
                              icon: const Icon(Symbols.content_copy),
                              label: const Text('Copy AI prompt'),
                            ),
                            TextButton(
                              onPressed: c.busy ? null : _settings,
                              child: const Text('Smart Import settings'),
                            ),
                            TextButton(
                              onPressed: c.busy ? null : _clear,
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(context)
                                    .colorScheme
                                    .error,
                              ),
                              child: const Text('Clear'),
                            ),
                          ],
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
