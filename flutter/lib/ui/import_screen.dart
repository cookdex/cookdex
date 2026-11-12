import 'pixel_scroll.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../import_controller.dart';
import '../import_service.dart';
import '../social_import_page.dart' show SocialSite;
import '../src/rust/api.dart' as core;
import 'components.dart';
import 'camera_permission.dart';
import 'feedback.dart';
import 'smart_settings_screen.dart';
import 'smart_action_button.dart';
import 'facelift_tokens.dart';
import 'navigation_feedback.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({
    super.key,
    required this.controller,
    required this.onReview,
    this.onTextReview,
    this.onTextBatch,
    this.initialInput,
    this.openUrl,
  });
  final ImportController controller;
  final Future<void> Function(String)? openUrl;
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
    with WidgetsBindingObserver, CameraPermissionFeedback<ImportScreen> {
  ImportController get c => widget.controller;
  bool get _disableContent => c.busy && c.phase == null;
  final _importButton = SmartActionButtonController();
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

  static const _aiSwitchHint =
      'For an AI import, turn on Use AI for this link, then tap Smart Import.';

  Future<void> _import({bool watchAnyway = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final discovery = await c.discover(
      watchAnyway: watchAnyway,
      onReady: (current) async {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && current()) await _importButton.flash();
      },
    );
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
    if (discovery.websiteAiHint && discovery.candidates.isNotEmpty) {
      final reviewEmbedded = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Embedded recipe needs review'),
          scrollable: true,
          content: Text([...discovery.warnings, _aiSwitchHint].join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Review embedded recipe'),
            ),
          ],
        ),
      );
      if (!mounted || reviewEmbedded != true) return;
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

  Future<void> _clear({bool wholeDraft = false}) async {
    if (!await confirmCookdex(
      context,
      title: wholeDraft ? 'Clear Smart Import?' : 'Clear ${c.tab.name}?',
      action: 'Clear',
      destructive: true,
    )) {
      return;
    }
    try {
      if (wholeDraft) {
        await c.clear();
      } else {
        await c.clearInput();
      }
      if (mounted) _syncFields();
    } catch (_) {
      c.error = 'Could not clear the import draft.';
      c.changed(clearError: false);
    }
  }

  Future<void> _paste() async {
    final tab = c.tab;
    try {
      final value = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (!mounted || c.tab != tab || c.busy || _backPending) return;
      if (value == null || value.isEmpty) {
        showFeedback(context, 'No text on the clipboard.');
        return;
      }
      final field = tab == ImportTab.link ? _link : _text;
      final selection = field.selection;
      final updated = selection.isValid
          ? field.text.replaceRange(selection.start, selection.end, value)
          : field.text + value;
      final offset =
          (selection.isValid ? selection.start : field.text.length) +
          value.length;
      field.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: offset),
      );
      if (tab == ImportTab.link) {
        c.link = updated;
      } else {
        c.text = updated;
      }
      c.changed();
    } catch (_) {
      if (mounted) {
        showFeedback(
          context,
          'Could not paste from the clipboard.',
          kind: FeedbackKind.error,
        );
      }
    }
  }

  Future<void> _copyPrompt() async {
    try {
      final prompt = await c.service.prompt();
      await Clipboard.setData(ClipboardData(text: prompt));
      if (mounted) showFeedback(context, 'AI prompt copied');
    } catch (_) {
      c.error = 'Could not copy the AI prompt.';
      c.changed(clearError: false);
    }
  }

  Widget _clearButton() => TextButton(
    onPressed: _disableContent ? null : () => _clear(),
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.error,
    ),
    child: const Text('Clear'),
  );

  void _switchTab(ImportTab tab) {
    if (c.tab == tab) return;
    FocusManager.instance.primaryFocus?.unfocus();
    c.tab = tab;
    c.changed();
  }

  Widget _selector() {
    const modes = [
      (ImportTab.text, 'Text', Symbols.article),
      (ImportTab.link, 'Link', Symbols.link),
      (ImportTab.photos, 'Photos', Symbols.photo_library),
    ];
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = Theme.of(context).textTheme.labelLarge!;
        final measure = TextPainter(
          text: TextSpan(text: 'Photos', style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final vertical = constraints.maxWidth < 8 + 3 * (measure.width + 44);
        measure.dispose();
        final buttons = [
          for (final (mode, label, icon) in modes)
            Semantics(
              selected: c.tab == mode,
              child: TextButton.icon(
                onPressed: _disableContent ? null : () => _switchTab(mode),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  backgroundColor: c.tab == mode
                      ? colors.primaryContainer
                      : null,
                  foregroundColor: c.tab == mode
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
                icon: Icon(icon, size: 18, fill: 1),
                label: Text(label),
              ),
            ),
        ];
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(vertical ? 20 : 40),
          ),
          child: vertical
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buttons,
                )
              : Row(
                  children: [
                    for (final button in buttons) Expanded(child: button),
                  ],
                ),
        );
      },
    );
  }

  Widget _switch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> change, {
    Color? offColor,
  }) {
    final off = WidgetStateProperty.resolveWith<Color?>(
      (states) =>
          states.contains(WidgetState.selected) ||
              states.contains(WidgetState.disabled)
          ? null
          : offColor,
    );
    return Material(
      borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SwitchListTile(
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(subtitle),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        thumbColor: off,
        trackOutlineColor: off,
        value: value,
        onChanged: _disableContent ? null : change,
      ),
    );
  }

  Widget _pasteButton() => FilledButton.tonalIcon(
    onPressed: _disableContent ? null : _paste,
    style: _smallButtonStyle(),
    icon: const Icon(Symbols.content_paste, size: 16),
    label: const Text('Paste'),
  );

  Widget _linkAction() {
    final empty = c.link.isEmpty;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 120);
    return FilledButton.tonal(
      onPressed: _disableContent ? null : (empty ? _paste : () => _clear()),
      style: _smallButtonStyle().copyWith(
        foregroundColor: empty
            ? null
            : WidgetStateProperty.resolveWith<Color?>(
                (states) => states.contains(WidgetState.disabled)
                    ? null
                    : Theme.of(context).colorScheme.error,
              ),
        minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      child: SizedBox(
        width: 22 + MediaQuery.textScalerOf(context).scale(40),
        child: Semantics(
          label: empty ? 'Paste' : 'Clear',
          child: ExcludeSemantics(
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              child: Row(
                key: ValueKey(empty),
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(empty ? Symbols.content_paste : Symbols.close, size: 16),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(empty ? 'Paste' : 'Clear'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(bool link) {
    final gate = c.linkGate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PixelScrollScope(
          axis: Axis.horizontal,
          builder: (context) => TextField(
            scrollController: PrimaryScrollController.of(context),
            controller: link ? _link : _text,
            enabled: !_disableContent,
            readOnly: c.busy,
            minLines: link ? 1 : 8,
            maxLines: link ? 1 : 12,
            keyboardType: link ? TextInputType.url : TextInputType.multiline,
            autocorrect: !link,
            decoration: InputDecoration(
              hintText: link ? 'Recipe link' : 'Paste recipe text',
              suffixIcon: link
                  ? Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Align(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: _linkAction(),
                      ),
                    )
                  : null,
            ),
            onChanged: (value) {
              if (link) {
                c.link = value;
              } else {
                c.text = value;
              }
              c.changed();
            },
          ),
        ),
        if (!link) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  children: [
                    _pasteButton(),
                    FilledButton.tonalIcon(
                      onPressed: _disableContent
                          ? null
                          : () async {
                              await c.pickText();
                              if (mounted) _syncFields();
                            },
                      style: _smallButtonStyle(),
                      icon: const Icon(Symbols.file_open, size: 16),
                      label: const Text('Open .txt file'),
                    ),
                  ],
                ),
              ),
              if (c.text.isNotEmpty) _clearButton(),
            ],
          ),
        ] else ...[
          if (gate != null) ...[
            const SizedBox(height: 8),
            _linkFallback(
              gate,
              keyNeeded: c.linkSite == SocialSite.youtube,
              manual:
                  c.linkSite != SocialSite.youtube &&
                  c.linkSite != SocialSite.pinterest,
            ),
          ] else if (c.canUseManualInput && c.error != null) ...[
            const SizedBox(height: 8),
            _linkFallback(
              c.error!,
              keyNeeded: c.linkResult?.needsYoutubeKey == true,
              manual: c.linkResult?.needsYoutubeKey != true,
            ),
          ],
          if (c.linkSite == null) ...[
            const SizedBox(height: 8),
            _switch(
              'Use AI for this link',
              'Gemini reads the page to extract the recipe.',
              c.useAiForLink,
              c.setUseAiForLink,
              offColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ],
    );
  }

  ButtonStyle _smallButtonStyle() => const ButtonStyle(
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
  );

  Future<void> _settings({bool keyPage = false}) async {
    if (keyPage) {
      await openGeminiKey(context, service: c.service, openUrl: widget.openUrl);
    } else {
      await openSmartSettings(
        context,
        service: c.service,
        preferences: c.preferences,
        openUrl: widget.openUrl,
      );
    }
    if (!mounted) return;
    if (keyPage || c.linkSite == SocialSite.youtube) {
      c.checkLinkKey(refresh: true);
      c.changed();
    }
  }

  Widget _linkFallback(
    String message, {
    required bool keyNeeded,
    required bool manual,
  }) {
    final theme = Theme.of(context);
    final retry = c.linkResult?.canRetryWatch == true;
    final watch = c.linkResult?.canWatchAnyway == true;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              child: Text(
                [
                  message,
                  if (c.showWebsiteAiHint) _aiSwitchHint,
                  if (manual) 'Choose or share up to 8 screenshots, or paste the recipe text.',
                ].join(' '),
              ),
            ),
            if (keyNeeded || retry || watch || manual) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (keyNeeded)
                    FilledButton(
                      onPressed: () => _settings(keyPage: true),
                      child: const Text('Add Gemini API key'),
                    ),
                  if (retry || watch)
                    FilledButton(
                      onPressed: () => _import(watchAnyway: watch),
                      child: Text(watch ? 'Watch anyway' : 'Try again'),
                    ),
                  if (manual) ...[
                    FilledButton.tonalIcon(
                      onPressed: () => _switchTab(ImportTab.photos),
                      style: _smallButtonStyle(),
                      icon: const Icon(Symbols.photo_library, size: 18),
                      label: const Text('Use photos'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _switchTab(ImportTab.text),
                      style: _smallButtonStyle(),
                      icon: const Icon(Symbols.content_paste, size: 18),
                      label: const Text('Paste text'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _photoPicker(bool camera) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: _disableContent || c.photos.length >= 8
          ? null
          : () => withCameraAccess(
              () => c.addPhotos(camera: camera),
              needsCamera: camera,
            ),
      style: TextButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainerHigh,
        foregroundColor: theme.colorScheme.onSurface,
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
        ),
        padding: const EdgeInsets.all(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              camera ? Symbols.photo_camera : Symbols.photo_library,
              fill: 1,
              size: 32,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            camera ? 'Camera' : 'Gallery',
            style: theme.textTheme.titleMedium,
          ),
          Text(
            camera ? 'Take a photo' : 'Pick photos',
            style: FaceliftTokens.tileSubtitle(context),
          ),
        ],
      ),
    );
  }

  Widget _thumbnails() => SizedBox(
    height: 112,
    child: PixelScrollScope(
      axis: Axis.horizontal,
      builder: (context) => ReorderableListView.builder(
        scrollController: PrimaryScrollController.of(context),
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: c.photos.length,
        onReorderItem: (from, to) {
          if (c.busy) return;
          c.photos.insert(to, c.photos.removeAt(from));
          c.changed();
        },
        itemBuilder: (context, index) {
          final photo = c.photos[index];
          return Padding(
            key: ValueKey(photo.id),
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 104,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ReorderableDelayedDragStartListener(
                      index: index,
                      enabled: !c.busy,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          photo.jpeg,
                          fit: BoxFit.cover,
                          semanticLabel:
                              'Photo ${index + 1}, hold and drag to reorder',
                          errorBuilder: (_, _, _) =>
                              const Center(child: Icon(Symbols.image)),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: 'Remove photo ${index + 1}',
                      onPressed: _disableContent
                          ? null
                          : () => c.removePhoto(index),
                      constraints: const BoxConstraints.tightFor(
                        width: 48,
                        height: 48,
                      ),
                      icon: CircleAvatar(
                        radius: 13,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Icon(
                          Symbols.close,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
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
  );

  Widget _photos() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final fontSize = Theme.of(context).textTheme.titleMedium!.fontSize!;
          final minTileWidth =
              28 + MediaQuery.textScalerOf(context).scale(fontSize) * 3.8;
          if ((constraints.maxWidth - 8) / 2 < minTileWidth) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _photoPicker(true),
                const SizedBox(height: 8),
                _photoPicker(false),
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _photoPicker(true)),
                const SizedBox(width: 8),
                Expanded(child: _photoPicker(false)),
              ],
            ),
          );
        },
      ),
      ?cameraPermissionNotice(),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(FaceliftTokens.groupRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${c.photos.length} of 8 photos',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ),
                if (c.photos.isNotEmpty) _clearButton(),
              ],
            ),
            if (c.photos.isNotEmpty) _thumbnails(),
          ],
        ),
      ),
      if (c.photoSavingAvailable) ...[
        const SizedBox(height: 10),
        _switch(
          'Save photos to device',
          'Camera and gallery photos are copied to the cookdex album when you save the recipe.',
          c.savePhotosToDevice,
          c.setSavePhotosToDevice,
        ),
      ],
    ],
  );

  static const _contentWidth = 760.0;
  double get _contentInset =>
      MediaQuery.sizeOf(context).shortestSide >= 600 ? 24 : 16;

  Widget _content() {
    final theme = Theme.of(context);
    final inset = _contentInset;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentWidth),
        child: PixelSingleChildScrollView(
          padding: EdgeInsets.fromLTRB(inset, 4, inset, 12),
          child: Semantics(
            blockUserActions: c.busy,
            child: IgnorePointer(
              ignoring: c.busy,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Turn a link, photos or pasted text into a recipe. You check it before it's saved.",
                    style: FaceliftTokens.tileSubtitle(context),
                  ),
                  const SizedBox(height: 16),
                  _selector(),
                  const SizedBox(height: 12),
                  if (c.tab == ImportTab.photos)
                    _photos()
                  else
                    _field(c.tab == ImportTab.link),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _disableContent ? null : _copyPrompt,
                        style: _smallButtonStyle(),
                        icon: const Icon(Symbols.content_copy, size: 16),
                        label: const Text('Copy AI prompt'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _disableContent ? null : () => _settings(),
                        style: _smallButtonStyle(),
                        icon: const Icon(Symbols.tune, size: 16),
                        label: const Text('Smart Import settings'),
                      ),
                    ],
                  ),
                  for (final warning in c.warnings)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(warning),
                    ),
                  if (c.error != null &&
                      !c.canUseManualInput &&
                      c.linkGate == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        c.error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  if (!c.hasInput && c.error != null)
                    TextButton(
                      onPressed: _disableContent
                          ? null
                          : () => _clear(wholeDraft: true),
                      child: const Text('Clear draft'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final inset = _contentInset;
    return SafeArea(
      top: false,
      maintainBottomViewPadding: true,
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _contentWidth),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset, 6, inset, inset),
              child: SmartActionButton(
                key: const Key('smart-import-action'),
                controller: _importButton,
                label: 'Smart Import',
                phase: c.phase?.label,
                onCancel: c.cancel,
                minHeight: 56,
                onPressed: c.busy || c.linkUnavailable ? null : _import,
              ),
            ),
          ),
        ),
      ),
    );
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
          bottomNavigationBar: c.loaded ? _footer() : null,
          child: !c.loaded
              ? const Center(child: CircularProgressIndicator())
              : ExcludeFocus(excluding: c.busy, child: _content()),
        ),
      ),
    ),
  );
}
