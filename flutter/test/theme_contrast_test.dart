import 'package:cookdex/sync_presentation.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  for (final scheme in [
    cookdexLightColors,
    cookdexColors,
    for (final brightness in Brightness.values)
      ColorScheme.fromSeed(seedColor: Colors.purple, brightness: brightness),
  ]) {
    test(
      '${scheme.brightness} theme contrast on requested surfaces ${scheme.primary}',
      () {
        for (final (name, foreground, background) in [
          ('body', scheme.onSurface, scheme.surface),
          ('shopping header', scheme.primary, scheme.surfaceContainerLow),
          (
            'shopping count',
            scheme.onSurfaceVariant,
            scheme.surfaceContainerLow,
          ),
          (
            'tonal chip',
            scheme.onSurfaceVariant,
            scheme.surfaceContainerHighest,
          ),
          ('cooking step', scheme.onSurface, scheme.primaryContainer),
          ('snackbar', scheme.onSurface, scheme.surfaceContainerHighest),
          ('snackbar action', scheme.primary, scheme.surfaceContainerHighest),
          ('warning', scheme.error, scheme.surfaceContainer),
        ]) {
          expect(
            contrast(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: name,
          );
        }
        for (final status in [
          syncFailureColor,
          syncConflictColor,
          syncPendingColor,
          syncCompleteColor,
          syncOffColor,
        ]) {
          final color = syncColorForBrightness(status, scheme.brightness);
          expect(
            contrast(color, scheme.surfaceContainerLow),
            greaterThanOrEqualTo(4.5),
            reason: 'sync label/dot',
          );
        }
      },
    );
  }
}
