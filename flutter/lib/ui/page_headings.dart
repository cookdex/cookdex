import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The heading and first content block share one inset on tabs and pushed pages.
abstract final class PageHeadings {
  static const side = 16.0;
  static const gap = 8.0;

  static TextStyle style(BuildContext context) =>
      Theme.of(context).textTheme.headlineSmall!
          .copyWith(fontSize: 24, fontWeight: FontWeight.w700);

  static double tabRowHeight(BuildContext context) {
    final title = style(context);
    return math.max(
      48,
      (MediaQuery.textScalerOf(context).scale(title.fontSize!) *
              (title.height ?? 1.33))
          .ceilToDouble(),
    );
  }
}

class TabHeading extends StatelessWidget {
  const TabHeading({
    super.key,
    required this.title,
    this.action,
    this.subtitle,
  });

  final Widget title;
  final Widget? action;
  final Widget? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PageHeadings.side,
      0,
      8,
      PageHeadings.gap,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: PageHeadings.tabRowHeight(context),
          ),
          child: Row(
            children: [
              Expanded(
                child: DefaultTextStyle(
                  style: PageHeadings.style(context),
                  child: Semantics(header: true, child: title),
                ),
              ),
              ?action,
            ],
          ),
        ),
        ?subtitle,
      ],
    ),
  );
}

/// The Scaffold gives its app bar a maximum height. Allow two title lines and
/// let the actual row wrap within the space left by Back and any route actions.
PreferredSizeWidget pageHeadingBar(
  BuildContext context, {
  required String title,
  Widget? leading,
  List<Widget>? actions,
  String? subtitle,
}) {
  final theme = Theme.of(context);
  final style = PageHeadings.style(context);
  final minHeight = PageHeadings.tabRowHeight(context);
  final background =
      theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;
  final brightness = ThemeData.estimateBrightnessForColor(background);
  final back =
      leading ??
      (ModalRoute.of(context)?.impliesAppBarDismissal == true
          ? const BackButton()
          : null);
  const leadingWidth = 56.0;
  const gap = 8.0;
  return PreferredSize(
    preferredSize: Size.fromHeight(minHeight * (subtitle == null ? 2 : 4)),
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: brightness,
        statusBarIconBrightness: brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Material(
        color: background,
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: minHeight),
                child: Row(
                  children: [
                    if (back != null)
                      SizedBox(
                        width: leadingWidth,
                        child: Center(heightFactor: 1, child: back),
                      ),
                    SizedBox(width: back == null ? PageHeadings.side : gap),
                    Expanded(
                      child: Semantics(
                        header: true,
                        namesRoute: true,
                        child: Text(
                          title,
                          style: style,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: PageHeadings.side),
                    ...?actions,
                  ],
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    back == null ? PageHeadings.side : leadingWidth + gap,
                    0,
                    PageHeadings.side,
                    PageHeadings.gap,
                  ),
                  child: Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
