import 'pixel_scroll.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../help_content.dart';
import 'feedback.dart';

class HowCookdexWorksScreen extends StatefulWidget {
  const HowCookdexWorksScreen({
    super.key,
    required this.loadAppInfo,
    required this.openUrl,
  });

  final Future<String> Function() loadAppInfo;
  final Future<void> Function(String) openUrl;

  @override
  State<HowCookdexWorksScreen> createState() => _HowCookdexWorksScreenState();
}

class _HowCookdexWorksScreenState extends State<HowCookdexWorksScreen> {
  bool _copying = false;

  Future<void> _copyAppInfo() async {
    if (_copying) return;
    setState(() => _copying = true);
    try {
      final info = await widget.loadAppInfo();
      await Clipboard.setData(ClipboardData(text: info));
      if (mounted) showFeedback(context, helpAppInfoCopied);
    } catch (_) {
      if (mounted) {
        showFeedback(context, helpAppInfoFailure, kind: FeedbackKind.error);
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _openLink(HelpLink link) async {
    try {
      await widget.openUrl(link.url);
    } catch (_) {
      if (mounted) {
        showFeedback(context, helpLinkFailure, kind: FeedbackKind.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(helpTitle)),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: PixelListView(
            key: const PageStorageKey('how-cookdex-works'),
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(helpIntroduction),
              ),
              for (final section in helpSections)
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    key: PageStorageKey('help-${section.id}'),
                    initiallyExpanded: section.id == 'start',
                    title: Text(section.title),
                    expandedAlignment: Alignment.centerLeft,
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (final paragraph in section.paragraphs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: _HelpParagraph(paragraph),
                          ),
                        ),
                      for (final link in section.links)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _openLink(link),
                            icon: const Icon(Symbols.open_in_new),
                            label: Text(link.label),
                          ),
                        ),
                      if (section.id == 'feedback')
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _copying ? null : _copyAppInfo,
                            icon: const Icon(Symbols.content_copy),
                            label: const Text(helpCopyAppInfo),
                          ),
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

class _HelpParagraph extends StatelessWidget {
  const _HelpParagraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final marker = RegExp(r'^(•|\d+\.) ').firstMatch(text);
    return Semantics(
      key: ValueKey('help-paragraph-$text'),
      label: text,
      excludeSemantics: true,
      child: marker == null
          ? Text(text)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(marker.group(1)!),
                const SizedBox(width: 8),
                Expanded(child: Text(text.substring(marker.end))),
              ],
            ),
    );
  }
}
