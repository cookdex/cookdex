import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../smart_create_controller.dart';
import '../src/rust/api.dart' show Candidate;
import 'components.dart';
import 'camera_permission.dart';
import 'facelift_motion.dart';
import 'facelift_tokens.dart';
import 'navigation_feedback.dart';
import 'pixel_scroll.dart';
import 'smart_action_button.dart';
import 'smart_create_controls.dart';
import 'smart_create_motion.dart';

part 'smart_create_check.dart';
part 'smart_create_ideas.dart';

class SmartCreateScreen extends StatefulWidget {
  const SmartCreateScreen({
    super.key,
    required this.controller,
    required this.onReview,
    required this.onKey,
    required this.onSettings,
    required this.onStaples,
    required this.onShop,
    this.onViewRecipe,
  });

  final SmartCreateController controller;
  final Future<void> Function(BuildContext, Candidate) onReview;
  final Future<void> Function(BuildContext) onKey, onSettings, onStaples;
  final Future<void> Function(List<String>) onShop;
  final Future<void> Function(String id)? onViewRecipe;

  @override
  State<SmartCreateScreen> createState() => _SmartCreateScreenState();
}

class _SmartCreateScreenState extends State<SmartCreateScreen>
    with WidgetsBindingObserver, CameraPermissionFeedback<SmartCreateScreen> {
  void _update(VoidCallback change) => setState(change);

  SmartCreateController get c => widget.controller;
  ThemeData get theme => Theme.of(context);
  ColorScheme get colors => theme.colorScheme;
  late final _typed = TextEditingController(text: c.typed);
  late final _mood = TextEditingController(text: c.mood);
  final _ideasScroll = PixelScrollController(keepScrollOffset: false);
  late int _visibleBatch;
  final _ingredientInput = TextEditingController();
  final _ingredientFocus = FocusNode();
  final _ingredientFieldKey = GlobalKey();
  bool _editingIngredient = false;
  double _ingredientInset = 0;
  double? _ingredientScrollOrigin;
  ({double inset, double pixels})? _ingredientSettling;
  Future<void> Function()? _retry;
  String? _openIdea;
  bool _optionsOpen = false;
  bool _addingToList = false;
  String? _shoppingErrorTitle;
  final _shoppingErrorKey = GlobalKey();

  final _optionsKey = GlobalKey();
  final _ideaKeys = <String, GlobalKey>{};
  final _working = {
    for (final action in ['photos', 'ideas', 'more', 'recipe'])
      action: SmartActionButtonController(),
  };
  Duration get _motion => FaceliftMotion.duration(context, MotionGroup.lists);
  bool get _busy => c.progress != null;
  String? _writingTitle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.onSuccessFlash = _flash;
    _visibleBatch = c.ideaBatchRevision;
    c.addListener(_followNewBatch);
  }

  @override
  void didChangeMetrics() => _ingredientMetricsChanged();

  @override
  void didUpdateWidget(SmartCreateScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != c) {
      oldWidget.controller.onSuccessFlash = null;
      oldWidget.controller.removeListener(_followNewBatch);
      c.onSuccessFlash = _flash;
      c.addListener(_followNewBatch);
      _visibleBatch = -1;
      _followNewBatch();
    }
  }

  void _followNewBatch() {
    if (_visibleBatch == c.ideaBatchRevision) return;
    _visibleBatch = c.ideaBatchRevision;
    _openIdea = null;
    if (_ideasScroll.hasClients) _ideasScroll.jumpTo(0);
  }

  Future<void> _flash() async {
    await _working[c.progressAction]?.flash();
  }

  Widget _sizeTransition({
    required Widget child,
    Alignment alignment = Alignment.topCenter,
    Curve curve = Curves.linear,
    VoidCallback? onEnd,
  }) {
    final duration = _motion;
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      onEnd: onEnd,
      child: child,
    );
  }

  @override
  void dispose() {
    c.onSuccessFlash = null;
    c.removeListener(_followNewBatch);
    WidgetsBinding.instance.removeObserver(this);
    _ingredientFocus.dispose();
    _ingredientInput.dispose();
    _ideasScroll.dispose();
    _typed.dispose();
    _mood.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_editingIngredient) _closeIngredient();
    FocusManager.instance.primaryFocus?.unfocus();
    _retry = action;
    await action();
  }

  Future<void> _review(CreateIdea idea) async {
    _writingTitle = idea.title;
    final candidate = await c.recipe(idea);
    if (mounted && candidate != null) {
      await widget.onReview(context, candidate);
    }
  }

  Future<void> _shop(CreateIdea idea) async {
    if (_addingToList) return;
    setState(() {
      _addingToList = true;
      _shoppingErrorTitle = null;
    });
    try {
      await widget.onShop(idea.missing);
      if (mounted) {
        c.markAdded(idea.title);
        HapticFeedback.selectionClick();
      }
    } catch (_) {
      if (mounted) {
        _shoppingErrorTitle = idea.title;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final target = _shoppingErrorKey.currentContext;
          if (target != null && _openIdea == idea.title) {
            Scrollable.ensureVisible(
              target,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
              duration: _motion,
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => _addingToList = false);
    }
  }

  void _back() {
    if (_editingIngredient) {
      _closeIngredient();
      return;
    }
    _retry = null;
    if (c.progress != null) c.cancel();
    if (c.step > 0) {
      c.back();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.maybePop(context);
      });
    }
  }

  Widget _steps() {
    final labels = [
      'What you have',
      if (!c.moodOnly || c.step == 1) 'Check',
      'Ideas',
    ];
    final current = c.step == 2 ? labels.length - 1 : c.step;
    return Semantics(
      label: 'Step ${current + 1} of ${labels.length}, ${labels[current]}',
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            children: [
              for (var index = 0; index < labels.length; index++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == labels.length - 1 ? 0 : 6,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: ColoredBox(
                        color: colors.outlineVariant,
                        child: TweenAnimationBuilder<double>(
                          duration: _motion,
                          tween: Tween(end: index <= current ? 1 : 0),
                          curve: Curves.easeOutCubic,
                          builder: (_, t, _) => Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: t,
                              child: ColoredBox(
                                color: colors.primary,
                                child: const SizedBox(height: 4),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (index, label) in labels.indexed)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == labels.length - 1 ? 0 : 8,
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: index == current
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: index == current
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _smart(
    String action,
    String label,
    VoidCallback? onPressed, {
    bool outlined = false,
  }) => SmartActionButton(
    controller: _working[action],
    label: label,
    phase: c.progressAction == action ? c.progress : null,
    onCancel: () {
      _retry = null;
      c.cancel();
    },
    onPressed: _busy && c.progressAction != action ? null : onPressed,
    outlined: outlined,
  );

  Widget _photoTile(bool camera) {
    final active = c.photos.length < 8;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: active
            ? () => _run(
                () => withCameraAccess(
                  () => c.pickPhotos(camera: camera),
                  needsCamera: camera,
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: active
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(
                    camera ? Symbols.photo_camera : Symbols.photo_library,
                    fill: 1,
                    size: 22,
                    color: active ? colors.primary : theme.disabledColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  camera ? 'Camera' : 'Gallery',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: active ? null : theme.disabledColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoTray() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${c.photos.length} of 8 photos',
                style: theme.textTheme.titleSmall,
              ),
            ),
            TextButton(
              onPressed: c.clearPhotos,
              style: TextButton.styleFrom(foregroundColor: colors.error),
              child: const Text('Clear'),
            ),
          ],
        ),
        SizedBox(
          height: 88,
          child: PixelSingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: CreateReflow(
              layout: (items) => Row(children: items.values.toList()),
              items: {
                for (final (index, photo) in c.photos.indexed)
                  photo.id: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox.square(
                      dimension: 88,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              photo.jpeg,
                              key: ValueKey(photo.id),
                              fit: BoxFit.cover,
                              cacheWidth: 192,
                              semanticLabel: 'Photo ${index + 1}',
                              errorBuilder: (_, _, _) =>
                                  const Icon(Symbols.image),
                            ),
                          ),
                          Align(
                            alignment: Alignment.topRight,
                            child: IconButton(
                              tooltip: 'Remove photo ${index + 1}',
                              onPressed: () => c.removePhoto(photo.id),
                              icon: CircleAvatar(
                                radius: 13,
                                backgroundColor: colors.surfaceContainerHighest,
                                child: Icon(
                                  Symbols.close,
                                  size: 16,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              },
            ),
          ),
        ),
      ],
    ),
  );

  Widget _moodField() => TextField(
    controller: _mood,
    textCapitalization: TextCapitalization.sentences,
    minLines: 1,
    maxLines: 3,
    textInputAction: TextInputAction.done,
    onChanged: c.setMood,
    decoration: const InputDecoration(
      labelText: 'In the mood for',
      hintText: 'Something cozy, spicy noodles, a quick lunch',
      hintMaxLines: 3,
      floatingLabelBehavior: FloatingLabelBehavior.always,
    ),
  );

  List<Widget> _input() => [
    TextField(
      controller: _typed,
      textCapitalization: TextCapitalization.none,
      minLines: 4,
      maxLines: 8,
      onChanged: c.setTyped,
      decoration: const InputDecoration(
        labelText: 'Ingredients',
        alignLabelWithHint: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        helperText: 'One per line, or separate them with commas',
        helperMaxLines: 2,
      ),
    ),
    const SizedBox(height: 16),
    _moodField(),
    const SizedBox(height: 16),
    Text('Add photos', style: theme.textTheme.titleSmall),
    const SizedBox(height: 8),
    LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <
            2 * (70 + MediaQuery.textScalerOf(context).scale(14) * 4)) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _photoTile(true),
              const SizedBox(height: 6),
              _photoTile(false),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _photoTile(true)),
            const SizedBox(width: 8),
            Expanded(child: _photoTile(false)),
          ],
        );
      },
    ),
    ?cameraPermissionNotice(),
    _sizeTransition(
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: _motion,
        child: c.photos.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _photoTray(),
              ),
      ),
    ),
    const SizedBox(height: 16),
    _options(),
  ];

  Widget _panel(
    Widget child, {
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) => Material(
    color: colors.surfaceContainer,
    borderRadius: BorderRadius.circular(FaceliftTokens.cardRadius),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );

  Widget _message() {
    final message = c.error ?? c.notice;
    final contents = AnimatedSwitcher(
      duration: _motion,
      child: message == null
          ? const SizedBox.shrink()
          : Padding(
              key: ValueKey(message),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: c.error == null ? null : colors.error,
                      ),
                    ),
                  ),
                  if (c.error != null)
                    Wrap(
                      spacing: 8,
                      children: [
                        if (c.needsKey)
                          TextButton(
                            onPressed: () => widget.onKey(context),
                            child: const Text('Set up Gemini key'),
                          ),
                        if (_retry != null)
                          TextButton(
                            onPressed: () => _run(_retry!),
                            child: const Text('Try again'),
                          ),
                        if (c.canUseFlash && _retry != null)
                          TextButton(
                            onPressed: () async {
                              final retry = _retry!;
                              await c.useFlash();
                              if (mounted) await _run(retry);
                            },
                            child: const Text('Use Flash'),
                          ),
                        if (!c.needsKey)
                          TextButton(
                            onPressed: () => widget.onSettings(context),
                            child: const Text('Smart Create settings'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
    // An incoming batch already occupies its final layout on the flash frame.
    // Its notice fades in there without moving cards during their cascade.
    if (c.step == 2) return contents;
    return _sizeTransition(alignment: Alignment.topLeft, child: contents);
  }

  Widget _footer() => SafeArea(
    top: false,
    child: Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: c.step == 2
                ? _newIdeasButton()
                : c.step == 1
                ? _smart(
                    'ideas',
                    'Get ideas',
                    c.ingredients.isEmpty
                        ? null
                        : () => _run(() {
                            _writingTitle = null;
                            return c.getIdeas();
                          }),
                  )
                : c.photos.isNotEmpty
                ? _smart('photos', 'Find ingredients', () => _run(c.next))
                : c.moodOnly
                ? _smart('ideas', 'Get ideas', () => _run(c.next))
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.tertiary,
                      foregroundColor: colors.onTertiary,
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: !c.hasTypedIngredients
                        ? null
                        : () => _run(c.next),
                    icon: const Icon(Symbols.arrow_forward),
                    label: const Text('Next'),
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _page(int index) => PixelSingleChildScrollView(
    key: PageStorageKey('smart-create-$index'),
    controller: index == 2 ? _ideasScroll : null,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
    child: ExcludeFocus(
      excluding: _busy && index < 2,
      child: IgnorePointer(
        ignoring: _busy && index < 2,
        child: RepaintBoundary(
          // The scroll transform changes each frame, but these chips and cards
          // do not. Keep their display list across drags; edits still repaint.
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (index == 0) ...[
                  Text(
                    "List what you have on hand, add photos, or say what you're in the mood for. You'll get meal ideas to match.",
                    style: FaceliftTokens.tileSubtitle(context),
                  ),
                  const SizedBox(height: 16),
                ],
                ...switch (index) {
                  0 => [..._input(), _message()],
                  1 => [..._check(), if (c.error != null) _message()],
                  _ => _ideas(),
                },
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => PopScope(
      canPop: c.step == 0 && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: CookdexFormScaffold(
        title: 'Smart Create',
        actions: [
          IconButton(
            tooltip: 'Smart Create settings',
            onPressed: () {
              if (!_busy) widget.onSettings(context);
            },
            icon: const Icon(Symbols.settings),
          ),
        ],
        bottomNavigationBar: _footer(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: _steps(),
                ),
                Expanded(
                  child: RetainedTabTransition(
                    index: c.step,
                    readyToWarm: false,
                    children: [
                      for (var i = 0; i < 3; i++)
                        Builder(builder: (_) => _page(i)),
                    ],
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

class _DashedOutline extends CustomPainter {
  const _DashedOutline(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(.5);
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          bounds,
          const Radius.circular(FaceliftTokens.tagRadius),
        ),
      );
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final line in outline.computeMetrics()) {
      for (var start = 0.0; start < line.length; start += 6) {
        canvas.drawPath(line.extractPath(start, start + 3), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) => oldDelegate.color != color;
}
