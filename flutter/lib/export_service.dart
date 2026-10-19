import 'shopping_sources.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import 'src/rust/api.dart' as core;

enum ExportAction { share, shareFile, copy, save }

/// Opening a share sheet does not prove that the receiving app sent anything.
enum ExportOutcome { shareOpened, copied, saved, cancelled, copiedFallback }

const cookdexGitHubUrl = 'https://github.com/cookdex/cookdex';
const cookdexDownloadUrl = '$cookdexGitHubUrl/releases/latest';
const cookdexShareText = 'Keep your recipes with cookdex.\n$cookdexDownloadUrl';

abstract class ExportPlatform {
  Future<ExportOutcome> shareText(String text, {required String title});
  Future<ExportOutcome> shareFile(String text, {required String filename});
  Future<ExportOutcome> copy(String text);
  Future<ExportOutcome> save(String text, {required String filename});
}

class NativeExportPlatform implements ExportPlatform {
  static const _channel = MethodChannel('com.sylph.cookdex.dev/export');

  Future<ExportOutcome> _native(
    String method,
    Map<String, String> arguments,
  ) async {
    final outcome = await _channel.invokeMethod<String>(method, arguments);
    return switch (outcome) {
      'opened' => ExportOutcome.shareOpened,
      'saved' => ExportOutcome.saved,
      'cancelled' => ExportOutcome.cancelled,
      _ => throw StateError('Export did not complete.'),
    };
  }

  @override
  Future<ExportOutcome> shareText(String text, {required String title}) =>
      _native('shareText', {'text': text, 'title': title});

  @override
  Future<ExportOutcome> shareFile(String text, {required String filename}) =>
      _native('shareFile', {'text': text, 'filename': filename});

  @override
  Future<ExportOutcome> save(String text, {required String filename}) =>
      _native('saveText', {'text': text, 'filename': filename});

  @override
  Future<ExportOutcome> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    return ExportOutcome.copied;
  }
}

class ExportService {
  ExportService({
    ExportPlatform? platform,
    Future<String> Function(core.Recipe)? exporter,
  }) : platform = platform ?? NativeExportPlatform(),
       _exporter = exporter ?? ((recipe) => core.exportText(recipe: recipe));

  final ExportPlatform platform;
  final Future<String> Function(core.Recipe) _exporter;
  static const maxBytes = 64 * 1024 * 1024;
  static const recipeTextMaxBytes = 5 * 1024 * 1024;

  Future<ExportOutcome> shareApp({required bool isAndroid}) => isAndroid
      ? platform.shareText(cookdexShareText, title: 'Share cookdex')
      : platform.copy(cookdexDownloadUrl);

  void _checkSize(String text) {
    if (utf8.encode(text).length > maxBytes) {
      throw StateError('Text export exceeds 64 MiB.');
    }
  }

  Future<ExportOutcome> recipe(core.Recipe recipe, ExportAction action) async {
    final text = await _exporter(recipe);
    if (utf8.encode(text).length > recipeTextMaxBytes) {
      throw StateError('Recipe text exceeds the 5 MiB import limit.');
    }
    return _dispatch(
      text,
      action,
      title: recipe.fields.title,
      filename: _filename(recipe.fields.title),
    );
  }

  Future<ExportOutcome> recipes(
    List<core.Recipe> recipes,
    ExportAction action,
  ) async {
    final text = await _recipeText(recipes);
    final title = recipes.length == 1
        ? recipes.single.fields.title
        : '${recipes.length} cookdex recipes';
    return _dispatch(text, action, title: title, filename: _filename(title));
  }

  Future<ExportOutcome> _dispatch(
    String text,
    ExportAction action, {
    required String title,
    required String filename,
  }) async {
    try {
      return await switch (action) {
        ExportAction.share => platform.shareText(text, title: title),
        ExportAction.shareFile => platform.shareFile(text, filename: filename),
        ExportAction.copy => platform.copy(text),
        ExportAction.save => platform.save(text, filename: filename),
      };
    } on MissingPluginException {
      if (action != ExportAction.share && action != ExportAction.shareFile) {
        rethrow;
      }
      await platform.copy(text);
      return ExportOutcome.copiedFallback;
    } on PlatformException catch (error) {
      if (error.code != 'unavailable' ||
          (action != ExportAction.share && action != ExportAction.shareFile)) {
        rethrow;
      }
      await platform.copy(text);
      return ExportOutcome.copiedFallback;
    }
  }

  Future<ExportOutcome> cookbook(List<core.Recipe> recipes) async => platform
      .save(await _recipeText(recipes), filename: 'cookdex-cookbook.txt');

  Future<String> _recipeText(List<core.Recipe> recipes) async {
    if (recipes.isEmpty) throw StateError('There are no recipes to export.');
    final text = StringBuffer();
    var bytes = 0;
    for (final recipe in recipes) {
      final value = await _exporter(recipe);
      bytes += utf8.encode(value).length + (text.isEmpty ? 0 : 2);
      if (bytes > recipeTextMaxBytes) {
        throw StateError('Cookbook text exceeds the 5 MiB import limit.');
      }
      if (text.isNotEmpty) text.write('\n\n');
      text.write(value);
    }
    return text.toString();
  }

  Future<ExportOutcome> shopping(
    List<core.ShoppingItem> items,
    List<core.RecipeSummary> recipes,
  ) async {
    if (items.isEmpty) throw StateError('The shopping list is empty.');
    final titles = {for (final recipe in recipes) recipe.id: recipe.title};
    final text = StringBuffer('Shopping list\n\n');
    for (final item in items) {
      final sources = item.contributorIds.toSet().map(
        (id) => _singleLine(
          (titles[id] ?? 'Deleted recipe') + shoppingScaleSuffix(item, id),
        ),
      );
      text.write('[${item.checked ? 'x' : ' '}] ${_singleLine(item.name)}');
      if (item.quantityText.isNotEmpty) {
        text.write(' — ${_singleLine(item.quantityText)}');
      }
      text.writeln(
        sources.isEmpty ? ' (Manual)' : ' (From: ${sources.join('; ')})',
      );
    }
    final value = text.toString();
    _checkSize(value);
    return platform.save(value, filename: 'cookdex-shopping-list.txt');
  }

  String _singleLine(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _filename(String title) {
    var name = title
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    name = String.fromCharCodes(name.runes.take(80));
    if (name.isEmpty) name = 'recipe';
    if (RegExp(
      r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
      caseSensitive: false,
    ).hasMatch(name)) {
      name = '_$name';
    }
    return '$name.txt';
  }
}
