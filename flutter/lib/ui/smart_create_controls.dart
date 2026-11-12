import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'facelift_motion.dart';

class CreateCountStepper extends StatelessWidget {
  const CreateCountStepper({
    super.key,
    required this.value,
    required this.maximum,
    required this.noun,
    required this.onChanged,
  });
  final int value, maximum;
  final String noun;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final buttonStyle = IconButton.styleFrom(
      backgroundColor: colors.surfaceContainerHighest,
      foregroundColor: colors.onSurface,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          tooltip: 'Fewer $noun',
          style: buttonStyle,
          onPressed: value <= 1 ? null : () => onChanged(value - 1),
          icon: const Icon(Symbols.remove, size: 20),
        ),
        _StepNumber(value),
        IconButton.filledTonal(
          tooltip: 'More $noun',
          style: buttonStyle,
          onPressed: value >= maximum ? null : () => onChanged(value + 1),
          icon: const Icon(Symbols.add, size: 20),
        ),
      ],
    );
  }
}

class _StepNumber extends StatefulWidget {
  const _StepNumber(this.value);
  final int value;

  @override
  State<_StepNumber> createState() => _StepNumberState();
}

class _StepNumberState extends State<_StepNumber> {
  int? _last;

  @override
  void didUpdateWidget(_StepNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _last = oldWidget.value;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700);
    final number = Text('${widget.value}', style: style);
    final duration = FaceliftMotion.accessible(
      context,
      const Duration(milliseconds: 180),
    );
    final last = _last;
    final direction = last != null && widget.value < last ? -1.0 : 1.0;
    return SizedBox(
      width: MediaQuery.textScalerOf(context).scale(16) + 18,
      child: Center(
        child: (last == null || duration == Duration.zero)
            ? number
            : ClipRect(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(widget.value),
                  duration: duration,
                  tween: Tween(begin: 0, end: 1),
                  child: number,
                  builder: (_, t, incoming) {
                    final enter = Curves.easeOutCubic.transform(t);
                    final exit = Curves.easeIn.transform(
                      (t * 180 / 160).clamp(0.0, 1.0),
                    );
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (exit < 1)
                          ExcludeSemantics(
                            child: Opacity(
                              opacity: 1 - exit,
                              child: Transform.translate(
                                offset: Offset(0, -14 * direction * exit),
                                child: Text('$last', style: style),
                              ),
                            ),
                          ),
                        Opacity(
                          opacity: enter,
                          child: Transform.translate(
                            offset: Offset(0, 14 * direction * (1 - enter)),
                            child: incoming,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
      ),
    );
  }
}

class CreateEffortBars extends StatelessWidget {
  const CreateEffortBars(this.count, this.color, {super.key});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (int i = 0; i < 3; i++)
        Container(
          width: 3.5,
          height: 6.0 + 3 * i,
          margin: EdgeInsetsDirectional.only(end: i == 2 ? 0 : 2),
          decoration: BoxDecoration(
            color: i < count ? color : color.withValues(alpha: .3),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ],
  );
}
