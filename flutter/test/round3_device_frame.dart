import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void round3SystemInsets(WidgetTester tester, {bool tablet = false}) {
  final inset = FakeViewPadding(bottom: 24 * tester.view.devicePixelRatio);
  tester.view.viewPadding = inset;
  tester.view.padding = inset;
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
}

Widget round3DeviceFrame(
  Widget child, {
  bool tablet = false,
  bool dark = false,
}) => Stack(
  alignment: Alignment.center,
  fit: StackFit.expand,
  children: [
    child,
    Positioned(
      bottom: 8,
      child: IgnorePointer(
        child: Container(
          width: tablet ? 140 : 108,
          height: 4,
          decoration: BoxDecoration(
            color: dark ? const Color(0xffc4c8c2) : const Color(0xff42463f),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    ),
  ],
);
