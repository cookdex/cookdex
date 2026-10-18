import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'navigation_feedback.dart';

/// Colors carried from the established cookdex recipe page.
const cookdexColors = ColorScheme.dark(
  primary: Color(0xffb7d0ac),
  onPrimary: Color(0xff172018),
  primaryContainer: Color(0xff29382c),
  onPrimaryContainer: Color(0xffe5e8e1),
  secondary: Color(0xffd3c48b),
  onSecondary: Color(0xff242315),
  secondaryContainer: Color(0xff202923),
  onSecondaryContainer: Color(0xffb7d0ac),
  surface: Color(0xff151918),
  surfaceContainerLowest: Color(0xff151918),
  surfaceContainerLow: Color(0xff171c1a),
  surfaceContainer: Color(0xff1c2220),
  surfaceContainerHigh: Color(0xff202923),
  surfaceContainerHighest: Color(0xff29382c),
  onSurface: Color(0xffe5e8e1),
  onSurfaceVariant: Color(0xffa3afa3),
  outline: Color(0xff46513b),
  outlineVariant: Color(0xff333c36),
  error: Color(0xfff0a799),
  onError: Color(0xff352623),
);

/// Warm paper surfaces and forest-green accents for daylight reading.
const cookdexLightColors = ColorScheme.light(
  primary: Color(0xff415f38),
  onPrimary: Color(0xffffffff),
  primaryContainer: Color(0xffd4e9c9),
  onPrimaryContainer: Color(0xff23351d),
  secondary: Color(0xff6b5d2f),
  onSecondary: Color(0xffffffff),
  secondaryContainer: Color(0xffeee3b8),
  onSecondaryContainer: Color(0xff30290f),
  surface: Color(0xfffafaf4),
  surfaceContainerLowest: Color(0xffffffff),
  surfaceContainerLow: Color(0xfff3f5ed),
  surfaceContainer: Color(0xffedf0e7),
  surfaceContainerHigh: Color(0xffe6eadf),
  surfaceContainerHighest: Color(0xffdfe4d7),
  onSurface: Color(0xff1b211b),
  onSurfaceVariant: Color(0xff4c584b),
  outline: Color(0xff717e6d),
  outlineVariant: Color(0xffc1cabb),
  error: Color(0xffa53628),
  onError: Color(0xffffffff),
  errorContainer: Color(0xffffdad3),
  onErrorContainer: Color(0xff3d0803),
);

ThemeData cookdexTheme({
  ColorScheme? colors,
  bool largerBody = false,
  double? snackBarBottomInset,
}) {
  final scheme = colors ?? cookdexColors;
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.copyWith(
    headlineLarge: base.textTheme.headlineLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    headlineMedium: base.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(
      height: 1.45,
      fontSize: largerBody ? 18 : 16,
    ),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(
      fontSize: largerBody ? 16 : 14,
    ),
    bodySmall: base.textTheme.bodySmall?.copyWith(
      fontSize: largerBody ? 14 : 12,
      color: scheme.onSurfaceVariant,
    ),
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  return base.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CookdexPageTransitionsBuilder(
          PredictiveBackPageTransitionsBuilder(),
        ),
        TargetPlatform.windows: CookdexPageTransitionsBuilder(
          FadeForwardsPageTransitionsBuilder(),
        ),
        TargetPlatform.linux: CookdexPageTransitionsBuilder(
          FadeForwardsPageTransitionsBuilder(),
        ),
        TargetPlatform.fuchsia: CookdexPageTransitionsBuilder(
          FadeForwardsPageTransitionsBuilder(),
        ),
        TargetPlatform.macOS: CookdexPageTransitionsBuilder(
          CupertinoPageTransitionsBuilder(),
        ),
        TargetPlatform.iOS: CookdexPageTransitionsBuilder(
          CupertinoPageTransitionsBuilder(),
        ),
      },
    ),
    textTheme: text,
    scaffoldBackgroundColor: scheme.surface,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      shape: shape,
      margin: EdgeInsets.zero,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outline),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      constraints: const BoxConstraints(maxWidth: 560),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: shape,
    ),
    snackBarTheme: SnackBarThemeData(
      insetPadding: snackBarBottomInset == null
          ? null
          : EdgeInsets.fromLTRB(16, 5, 16, snackBarBottomInset),
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
      actionTextColor: scheme.primary,
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    hoverColor: scheme.primary.withValues(alpha: .08),
    focusColor: scheme.primary.withValues(alpha: .18),
    highlightColor: scheme.primary.withValues(alpha: .12),
  );
}
