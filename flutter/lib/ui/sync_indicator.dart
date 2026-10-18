import 'package:flutter/material.dart';

import '../sync_presentation.dart';

class SyncIndicator extends StatelessWidget {
  const SyncIndicator({super.key, required this.status, required this.onTap});
  final SyncPresentation status;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = syncColorForBrightness(
      status.color,
      Theme.of(context).brightness,
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    if (duration == Duration.zero) {
      return TextButton(
        onPressed: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(
              status.label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: color),
            ),
          ],
        ),
      );
    }
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(48, 48),
        foregroundColor: color,
      ),
      child: AnimatedSize(
        duration: duration,
        curve: Curves.easeInOut,
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: duration,
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            AnimatedSwitcher(
              duration: duration,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerRight,
                children: [
                  ...previous.map(
                    (child) => Positioned(right: 0, child: child),
                  ),
                  ?current,
                ],
              ),
              child: Text(
                status.label,
                key: ValueKey(status.label),
                maxLines: 1,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
