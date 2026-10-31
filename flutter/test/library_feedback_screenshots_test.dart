import 'dart:io';
import 'dart:ui' as ui;

import 'package:cookdex/local_preferences.dart';
import 'package:cookdex/recipe_store.dart';
import 'package:cookdex/ui/app.dart';
import 'package:cookdex/ui/library_screen.dart';
import 'package:cookdex/ui/theme.dart';
import 'package:cookdex/library_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ingredient_section_screenshots_test.dart' show loadSectionCaptureFonts;
import 'library_screen_test.dart'
    show
        LibraryFakeRepository,
        libraryFixtures,
        libraryFeedbackFixtures,
        overlappingLibraryFixture;
import 'import_test.dart' show ShellPlatform, ImportFakeService;

// Flutter host renders omit the OS cursor. This capture-only overlay marks the
// exact coordinate used by the mouse gesture; it never changes app behavior.
class _Pointer extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, 23)
      ..lineTo(6, 18)
      ..lineTo(11, 29)
      ..lineTo(16, 27)
      ..lineTo(11, 16)
      ..lineTo(20, 16)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawPath(path, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_Pointer old) => false;
}

void main() {
  testWidgets('Library feedback approval states', (tester) async {
    await loadSectionCaptureFonts(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final pointer = ValueNotifier<Offset?>(null);
    final files = <String>[];
    RecipeStore? store;
    LocalPreferences? prefs;
    for (final dark in [false, true]) {
      Future<void> mount({
        bool many = false,
        bool overlap = false,
        bool settings = false,
        bool windows = false,
        Size size = const Size(390, 844),
      }) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        store?.dispose();
        prefs?.dispose();
        tester.view.physicalSize = size;
        pointer.value = null;
        prefs = LocalPreferences.memory()
          ..setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
        store = RecipeStore(
          LibraryFakeRepository(
            overlap
                ? [overlappingLibraryFixture()]
                : many
                ? libraryFeedbackFixtures()
                : libraryFixtures(),
          ),
          prefs!,
        );
        await store!.initialize();
        final app = settings
            ? CookdexApp(
                store: store!,
                platform: ShellPlatform(),
                importService: ImportFakeService(),
              )
            : MaterialApp(
                debugShowCheckedModeBanner: false,
                theme:
                    cookdexTheme(
                      colors: dark ? cookdexColors : cookdexLightColors,
                    ).copyWith(
                      platform: windows
                          ? TargetPlatform.windows
                          : TargetPlatform.android,
                    ),
                home: const SizedBox.shrink(),
                initialRoute: '/library',
                routes: {
                  '/library': (_) =>
                      LibraryScreen(store: store!, onOpenRecipe: (_, _) {}),
                },
              );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('capture'),
            child: Stack(
              textDirection: TextDirection.ltr,
              children: [
                Positioned.fill(child: app),
                ValueListenableBuilder<Offset?>(
                  valueListenable: pointer,
                  builder: (_, point, _) => point == null
                      ? const SizedBox.shrink()
                      : Positioned(
                          left: point.dx,
                          top: point.dy,
                          child: IgnorePointer(
                            child: CustomPaint(
                              size: const Size(24, 32),
                              painter: _Pointer(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> capture(String state) async {
        expect(tester.takeException(), isNull, reason: state);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture')),
        );
        final name = '${dark ? 'dark' : 'light'}-$state.png';
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(
            '../artifacts/library-tidy/checkpoint-2/screens/$name',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        files.add(name);
      }

      Future<void> tap(String text) async {
        await tester.tap(find.text(text).first);
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await mount(settings: true);
      await tap('Settings');
      await capture('settings');
      await mount(many: true);
      await capture('many-duplicates');
      await tap('Show all (6)');
      await capture('all-duplicates');
      final group = find.ancestor(
        of: find.text('Parm.'),
        matching: find.byType(Card),
      );
      await tester.ensureVisible(group);
      await tester.tap(
        find.descendant(of: group, matching: find.text('Merge')),
      );
      await tester.pumpAndSettle();
      await capture('duplicate-choices');
      await tester.tap(
        find.widgetWithText(RadioListTile<LibraryName>, 'Parm.'),
      );
      await tester.pumpAndSettle();
      await capture('duplicate-alternate');
      await tester.tap(find.widgetWithText(TextButton, 'Merge').last);
      await tester.pumpAndSettle();
      await capture('undo');
      await tap('Undo');
      await mount();
      await tap('parm');
      await tap('Rename');
      await tester.enterText(find.byType(TextField).last, 'parmesan cheese');
      await tester.pumpAndSettle();
      await capture('rename-warning');
      await mount(overlap: true);
      await tap('Eggs');
      await capture('overlap-details');
      await tap('Merge into…');
      await tap('Egg');
      await capture('plural-merge');
      await tap('Cancel');
      await back();
      await tap('Egg');
      await tap('Rename');
      await tester.enterText(find.byType(TextField).last, 'Eggs');
      await tester.pumpAndSettle();
      await tap('Continue');
      await capture('plural-rename');
      await mount();
      await tap('Tags');
      await tap('weeknight');
      await tap('Remove tag');
      await capture('remove-tag');
      await mount(size: const Size(1280, 800));
      await tap('parm');
      await capture('tablet-ingredients');
      await tap('Tags');
      await tap('weeknight');
      await capture('tablet-tags');
      await mount(windows: true, size: const Size(1600, 900));
      await tap('Tags');
      await tap('weeknight');
      final row = find.byKey(
        const ValueKey(('library-name', false, 'Weeknight')),
      );
      final point = tester.getTopLeft(row) + const Offset(130, 24);
      final mouse = await tester.startGesture(
        point,
        kind: ui.PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.up();
      pointer.value = point;
      await tester.pumpAndSettle();
      await capture('windows-pointer');
      pointer.value = null;
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Rename'));
      await tester.pumpAndSettle();
      await capture('windows-row-rename');
      await mouse.removePointer();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    store?.dispose();
    prefs?.dispose();
    pointer.dispose();
    await tester.runAsync(
      () async =>
          File('../artifacts/library-tidy/checkpoint-2/screens/manifest.txt')
              .writeAsString('${files.join('\n')}\n'),
    );
    debugDisableShadows = true;
  }, skip: Platform.environment['LIBRARY_FEEDBACK_SCREENSHOTS'] != '1');
}
