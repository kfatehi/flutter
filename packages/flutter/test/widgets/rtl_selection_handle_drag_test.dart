// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Widget-level tests for which end of a right-to-left selection each handle drags.
//
// test/rendering/editable_rtl_selection_endpoints_test.dart covers the geometry one layer down:
// getEndpointsForSelection must return the selection's visual extremes. This file covers the
// consequence a user actually feels — the handle drawn on the left of a selection must be the one
// that moves the left-hand end of it.
//
// The binding is fixed: the start handle drags `base` and the end handle drags `extent`
// (_handleSelectionStartHandleDragUpdate / _handleSelectionEndHandleDragUpdate). So a handle drags
// the end the user grabbed if and only if it is PAINTED at the caret for the offset it is bound
// to. When the endpoints come back in the wrong order that stops being true: the handle on the
// left is bound to the offset on the right, and dragging it runs away from the finger. These
// tests assert the painted position of each handle against the caret for its own offset, which is
// exactly that condition.
//
// Handle positions are read from the rendered handle widgets rather than from
// getEndpointsForSelection, so the tests do not assume the value they are checking. Which handle
// is which comes from build order — the start handle's overlay entry is built first — the same
// assumption test/widgets/text_selection_test.dart's directionality tests already rely on.
//
// Everything uses the test font: the several boxes on one line come from differing style runs
// rather than from shaping, so no font asset is required.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editable_text_tester.dart';
import 'editable_text_utils.dart';

// Logically first is drawn RIGHTmost in RTL, logically last LEFTmost.
const String _rtlRun1 = 'خانه ';
const String _rtlRun2 = 'نشسته ';
const String _rtlRun3 = 'ام';
const String _rtlText = '$_rtlRun1$_rtlRun2$_rtlRun3';

const String _ltrRun1 = 'one ';
const String _ltrRun2 = 'two ';
const String _ltrRun3 = 'six';
const String _ltrText = '$_ltrRun1$_ltrRun2$_ltrRun3';

/// A controller that paints its text as three style runs.
///
/// Differing [FontWeight] is enough to split one line into several selection boxes with the test
/// font, which is what makes the multi-box code path reachable without shaping.
class _StyledRunsController extends TextEditingController {
  _StyledRunsController({required super.text, required this.boundaries});

  /// The two offsets at which the style changes.
  final (int, int) boundaries;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final (int first, int second) = boundaries;
    return TextSpan(
      style: style,
      children: <InlineSpan>[
        TextSpan(
          text: text.substring(0, first),
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
        TextSpan(
          text: text.substring(first, second),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        TextSpan(text: text.substring(second), style: const TextStyle(fontWeight: FontWeight.w400)),
      ],
    );
  }
}

/// A built handle, tagged so the test can find it again and measure where it was painted.
class _HandleMarker extends StatelessWidget {
  const _HandleMarker({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(width: 40, height: 40);
}

/// Records the handles as they are built, in order: start handle first, then end handle.
class _HandleSpyControls extends TextSelectionControls with TextSelectionHandleControls {
  final List<TextSelectionHandleType> builtTypes = <TextSelectionHandleType>[];
  final List<Key> builtKeys = <Key>[];

  void clear() {
    builtTypes.clear();
    builtKeys.clear();
  }

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final Key key = ValueKey<int>(builtKeys.length);
    builtTypes.add(type);
    builtKeys.add(key);
    return _HandleMarker(key: key);
  }

  // The handle hangs below the line from its anchor, so the point it marks is the middle of its
  // top edge.
  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) =>
      const Offset(20, 0);

  @override
  Size getHandleSize(double textLineHeight) => const Size(40, 40);
}

class _Field {
  _Field(this.controller, this.controls);

  final TextEditingController controller;
  final _HandleSpyControls controls;
}

Future<_Field> _pumpField(
  WidgetTester tester, {
  required String text,
  required (int, int) boundaries,
  required TextDirection direction,
  required TextSelection selection,
}) async {
  final TextEditingController controller = _StyledRunsController(
    text: text,
    boundaries: boundaries,
  );
  final focusNode = FocusNode();
  final controls = _HandleSpyControls();
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);

  await tester.pumpWidget(
    TestWidgetsApp(
      home: Directionality(
        textDirection: direction,
        child: Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: TestTextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: null,
              style: const TextStyle(fontSize: 14.0, height: 1.0),
              selectionControls: controls,
              showSelectionHandles: true,
              selectAllOnFocus: false,
            ),
          ),
        ),
      ),
    ),
  );

  focusNode.requestFocus();
  await tester.pump();
  controls.clear();
  controller.selection = selection;
  await tester.pumpAndSettle();
  return _Field(controller, controls);
}

/// Where the handle bound to [base]/[extent] was painted, in global x.
///
/// Index 0 is the start handle (which drags `base`), index 1 the end handle (which drags
/// `extent`).
double _handleX(WidgetTester tester, _Field field, int index) {
  expect(
    field.controls.builtKeys.length,
    2,
    reason: 'a non-collapsed selection must build exactly two handles',
  );
  return tester.getRect(find.byKey(field.controls.builtKeys[index])).center.dx;
}

/// Where the caret for [offset] is painted, in global x.
double _caretX(WidgetTester tester, int offset) {
  final RenderEditable renderEditable = findRenderEditable(tester);
  final Rect local = renderEditable.getLocalRectForCaret(TextPosition(offset: offset));
  return renderEditable.localToGlobal(local.center).dx;
}

void main() {
  testWidgets('setup guard: the RTL selection spans several boxes on one line, with two handles', (
    WidgetTester tester,
  ) async {
    const selection = TextSelection(baseOffset: 2, extentOffset: 10);
    final _Field field = await _pumpField(
      tester,
      text: _rtlText,
      boundaries: (_rtlRun1.length, _rtlRun1.length + _rtlRun2.length),
      direction: TextDirection.rtl,
      selection: selection,
    );

    // If any of this fails the rest of the file is not testing what it claims to.
    final List<ui.TextBox> boxes = findRenderEditable(tester).getBoxesForSelection(selection);
    expect(boxes.length, greaterThan(1), reason: 'the selection must span several boxes');
    expect(
      boxes.every((ui.TextBox box) => box.top == boxes.first.top),
      isTrue,
      reason: 'all boxes must be on ONE line; multi-line is a different code path',
    );
    expect(
      boxes.every((ui.TextBox box) => box.direction == TextDirection.rtl),
      isTrue,
      reason: 'this is a pure RTL selection; no box may be bidi-flipped',
    );
    expect(field.controls.builtKeys.length, 2, reason: 'both handles must be built');
  });

  testWidgets('each RTL handle is painted at the caret for the offset it drags', (
    WidgetTester tester,
  ) async {
    const selection = TextSelection(baseOffset: 2, extentOffset: 10);
    final _Field field = await _pumpField(
      tester,
      text: _rtlText,
      boundaries: (_rtlRun1.length, _rtlRun1.length + _rtlRun2.length),
      direction: TextDirection.rtl,
      selection: selection,
    );

    // Native parity: a native Android EditText draws a pure-RTL selection with the
    // text_select_handle_right drawable at the right-hand (start) end and
    // text_select_handle_left at the left-hand (end) one. Measured on a device against this same
    // string. This holds before and after the endpoint fix — the glyphs were never the defect —
    // and is asserted so a change to the geometry cannot quietly take the types with it.
    expect(field.controls.builtTypes, <TextSelectionHandleType>[
      TextSelectionHandleType.right,
      TextSelectionHandleType.left,
    ]);

    // The start handle drags `base` and the end handle drags `extent`. Painting either one
    // somewhere other than its own caret is what makes a drag move the opposite end.
    expect(
      _handleX(tester, field, 0),
      closeTo(_caretX(tester, selection.baseOffset), 2),
      reason: 'the handle that drags base must be painted at the caret for base',
    );
    expect(
      _handleX(tester, field, 1),
      closeTo(_caretX(tester, selection.extentOffset), 2),
      reason: 'the handle that drags extent must be painted at the caret for extent',
    );
  });

  testWidgets('the RTL handle drawn on the left is the one that drags the left-hand end', (
    WidgetTester tester,
  ) async {
    const selection = TextSelection(baseOffset: 2, extentOffset: 10);
    final _Field field = await _pumpField(
      tester,
      text: _rtlText,
      boundaries: (_rtlRun1.length, _rtlRun1.length + _rtlRun2.length),
      direction: TextDirection.rtl,
      selection: selection,
    );

    // Same requirement as above, stated the way a user would notice it failing. Derive which
    // offset is visually on the left rather than assuming; in RTL it is the extent.
    final bool extentIsOnTheLeft =
        _caretX(tester, selection.extentOffset) < _caretX(tester, selection.baseOffset);
    expect(extentIsOnTheLeft, isTrue, reason: 'in RTL the extent is the left-hand end');

    final double startHandleX = _handleX(tester, field, 0);
    final double endHandleX = _handleX(tester, field, 1);

    expect(
      endHandleX,
      lessThan(startHandleX),
      reason: 'the handle drawn on the left must be the one bound to the left-hand end (extent)',
    );
  });

  testWidgets('control: each LTR handle is painted at the caret for the offset it drags', (
    WidgetTester tester,
  ) async {
    // Visual and logical order agree in LTR, so this holds with or without the fix. It guards
    // against a fix that "corrects" the direction that was never broken.
    const selection = TextSelection(baseOffset: 2, extentOffset: 10);
    final _Field field = await _pumpField(
      tester,
      text: _ltrText,
      boundaries: (_ltrRun1.length, _ltrRun1.length + _ltrRun2.length),
      direction: TextDirection.ltr,
      selection: selection,
    );

    expect(_handleX(tester, field, 0), closeTo(_caretX(tester, selection.baseOffset), 2));
    expect(_handleX(tester, field, 1), closeTo(_caretX(tester, selection.extentOffset), 2));
    expect(
      _handleX(tester, field, 0),
      lessThan(_handleX(tester, field, 1)),
      reason: 'in LTR the base is the left-hand end, so its handle is the left one',
    );
  });

  testWidgets('control: a single-box RTL selection paints its handles correctly', (
    WidgetTester tester,
  ) async {
    // One style run means one box, and that case is right before any fix — which is why the
    // defect stays invisible until a selection crosses a run boundary.
    const selection = TextSelection(baseOffset: 1, extentOffset: 4);
    final _Field field = await _pumpField(
      tester,
      text: _rtlText,
      boundaries: (_rtlRun1.length, _rtlRun1.length + _rtlRun2.length),
      direction: TextDirection.rtl,
      selection: selection,
    );
    expect(findRenderEditable(tester).getBoxesForSelection(selection).length, 1);

    expect(_handleX(tester, field, 0), closeTo(_caretX(tester, selection.baseOffset), 2));
    expect(_handleX(tester, field, 1), closeTo(_caretX(tester, selection.extentOffset), 2));
  });
}
