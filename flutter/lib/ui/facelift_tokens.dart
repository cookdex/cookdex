import 'package:flutter/material.dart';

/// Shape and type choices for the facelift surfaces, scoped to their roles.
abstract final class FaceliftTokens {
  static const cardRadius = 18.0;
  static const groupRadius = 20.0;
  static const tagRadius = 8.0;
  static const filterRadius = 10.0;
  static const addRadius = 18.0;
  static const sheetRadius = 28.0;
  static const sheetSide = 16.0;
  static const sheetBottom = 32.0;
  static const sheetHeadingInset = 32.0;
  static const tileGap = 10.0;
  static const sheetIconSize = 50.0;
  static const sheetIconRadius = 16.0;
  static const quickIconSize = 44.0;
  static const quickIconRadius = 14.0;
  static const categoryIconSize = 30.0;
  static const categoryIconRadius = 10.0;

  static TextStyle sheetTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleLarge!
          .copyWith(fontSize: 20, fontWeight: FontWeight.w700);
  static TextStyle categoryTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      );
  static TextStyle tileTitle(BuildContext context) =>
      Theme.of(context).textTheme.titleMedium!
          .copyWith(fontSize: 18, fontWeight: FontWeight.w600);
  static TextStyle tileSubtitle(BuildContext context) => Theme.of(context)
      .textTheme
      .bodyMedium!
      .copyWith(
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
  static TextStyle quickLabel(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge!
          .copyWith(fontSize: 13, fontWeight: FontWeight.w600);
}
