// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression tests for the box RenderEditable.getEndpointsForSelection picks as the
// holder of a right-to-left selection's logical START.
//
// The two sibling files cover which LINE each endpoint comes from:
//   editable_rtl_selection_endpoints_test.dart           — a selection on one line
//   editable_rtl_multiline_selection_endpoints_test.dart — a selection spanning lines
// This one covers the choice WITHIN a line, which is a separate assumption.
//
// Within one line the boxes of a selection arrive in visual (left to right) order, so
// on a right-to-left line the logically first box is the visually last one. Reading it
// as the LAST box of the line is not the same thing, because the engine can emit boxes
// that are not part of that left-to-right walk:
//
//   * Under BoxWidthStyle.max — RenderEditable's own default — SkParagraph adds a
//     line-fill box so a multi-line selection reads as contiguous. For a right-to-left
//     line it adds that fill for a selection that does NOT reach the line's logical
//     end, and inserts it AFTER the selection's real box (see the sweep in
//     flutter/flutter#39755's family; the fill runs from the selection's left edge to
//     x = 0 regardless of where the line starts).
//   * A line ending in a hard break after trailing whitespace can carry a separate
//     trailing-space box, appended after the run's own box, whose right edge is inside
//     the line.
//
// Either one makes the line's LAST box a box that is not its rightmost, and the start
// endpoint — the anchor the start selection handle is painted at — then lands inside
// the selection instead of on its trailing edge.
//
// The fix does not rely on list order for that choice: within the identified first
// line it takes the box with the greatest `right`. The engine's extra boxes are always
// emitted after a line's real boxes and never extend further right than the real box
// they were derived from, so the greatest `right` is the same box the left-to-right
// walk would have ended on when there are no extras.
//
// The mirror rule for the END endpoint is deliberately NOT "the smallest left". The
// BoxWidthStyle.max fill extends to x = 0, so the smallest left is the fill box and
// choosing it moves the end endpoint to the paragraph edge — measured. The first box
// of the last line is already safe: extras are appended after a line's real boxes, so
// a line's FIRST box is always a real one.
//
// No font asset is needed. The trigger is the engine's box LIST, not a font metric,
// and the test font produces it under BoxWidthStyle.max.

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'rendering_tester.dart';

class _FakeEditableTextState with TextSelectionDelegate {
  @override
  TextEditingValue textEditingValue = TextEditingValue.empty;

  @override
  void hideToolbar([bool hideHandles = true]) {}

  @override
  void userUpdateTextEditingValue(TextEditingValue value, SelectionChangedCause? cause) {}

  @override
  void bringIntoView(TextPosition position) {}

  @override
  void cutSelection(SelectionChangedCause cause) {}

  @override
  Future<void> pasteText(SelectionChangedCause cause) async {}

  @override
  void selectAll(SelectionChangedCause cause) {}

  @override
  void copySelection(SelectionChangedCause cause) {}
}

const double _fontSize = 20;
const double _viewportWidth = 300;

// Soft wraps into three lines at _viewportWidth with the test font. The second line
// is narrower than the paragraph, which is what gives the fill box something to fill.
const String _rtlText = 'سلام دوست عزیز من خوب هستم ممنون از تو';
const String _ltrText = 'hello dear friend of mine i am well thanks';

// A whole word in the middle of the second line: it reaches neither end of its line.
const TextSelection _midLineWord = TextSelection(baseOffset: 18, extentOffset: 21);

RenderEditable _laidOut(
  String text,
  TextSelection selection,
  TextDirection direction, {
  ui.BoxWidthStyle widthStyle = ui.BoxWidthStyle.max,
}) {
  final editable = RenderEditable(
    text: TextSpan(text: text, style: const TextStyle(fontSize: _fontSize)),
    textDirection: direction,
    startHandleLayerLink: LayerLink(),
    endHandleLayerLink: LayerLink(),
    offset: ViewportOffset.zero(),
    textSelectionDelegate: _FakeEditableTextState(),
    selection: selection,
    maxLines: null,
    // Pinned rather than defaulted, so the premise of the suite is stated where it can
    // be read. This is the value RenderEditable itself defaults to.
    selectionWidthStyle: widthStyle,
  );
  layout(editable, constraints: const BoxConstraints(maxWidth: _viewportWidth));
  return editable;
}

void main() {
  TestRenderingFlutterBinding.ensureInitialized();

  test('setup guard: the selected word sits mid-line, reaching neither end of its line', () {
    final RenderEditable editable = _laidOut(_rtlText, _midLineWord, TextDirection.rtl);
    final Rect start = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.start));
    final Rect end = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.end));

    expect(start.top, end.top, reason: 'guard: the selection must live on ONE line');
    expect(
      start.center.dx,
      greaterThan(end.center.dx),
      reason: 'guard: in RTL the logical start is to the RIGHT of the logical end',
    );

    final List<ui.TextBox> boxes = editable.getBoxesForSelection(_midLineWord);
    final double lineRight =
        boxes.map((ui.TextBox b) => b.right).reduce((double a, double b) => a > b ? a : b);
    final double lineLeft =
        boxes.map((ui.TextBox b) => b.left).reduce((double a, double b) => a < b ? a : b);
    expect(
      lineRight,
      greaterThan(start.center.dx - 1),
      reason: 'guard: some box reaches the selection trailing edge',
    );
    expect(lineLeft, lessThan(end.center.dx), reason: 'guard: some box reaches past the leading edge');
  });

  test('setup guard: the engine emits a box list that is NOT in visual order', () {
    final RenderEditable editable = _laidOut(_rtlText, _midLineWord, TextDirection.rtl);
    final List<ui.TextBox> boxes = editable.getBoxesForSelection(_midLineWord);

    expect(
      boxes.length,
      greaterThan(1),
      reason: 'BoxWidthStyle.max must add a fill box for this RTL mid-line selection; '
          'without it this suite tests nothing',
    );
    final double maxRight =
        boxes.map((ui.TextBox b) => b.right).reduce((double a, double b) => a > b ? a : b);
    expect(
      boxes.last.right,
      lessThan(maxRight),
      reason: 'the LAST box of the line must not be its rightmost — that is the '
          'out-of-order box this suite exists for',
    );
  });

  test('the start endpoint of an RTL selection sits where the caret for its offset sits', () {
    final RenderEditable editable = _laidOut(_rtlText, _midLineWord, TextDirection.rtl);
    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_midLineWord);
    expect(endpoints.length, 2);

    final Rect startCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.start));
    expect(
      endpoints.first.point.dx,
      closeTo(startCaret.center.dx, 3),
      reason: 'the start endpoint must coincide with the caret at the selection start, '
          'not with an engine-added box inside the selection',
    );
  });

  test('the start endpoint is not inside the selection', () {
    final RenderEditable editable = _laidOut(_rtlText, _midLineWord, TextDirection.rtl);
    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_midLineWord);

    final Rect startCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.start));
    final Rect endCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.end));
    // RTL: the selection occupies x from endCaret to startCaret. Its start handle
    // belongs on the right edge of that span, never between the two.
    expect(
      endpoints.first.point.dx,
      greaterThan(endCaret.center.dx + 1),
      reason: 'the start endpoint fell between the selection edges',
    );
    expect(endpoints.first.point.dx, closeTo(startCaret.center.dx, 3));
  });

  test('the end endpoint of the same selection is unaffected', () {
    final RenderEditable editable = _laidOut(_rtlText, _midLineWord, TextDirection.rtl);
    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_midLineWord);

    final Rect endCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.end));
    expect(
      endpoints.last.point.dx,
      closeTo(endCaret.center.dx, 3),
      reason: 'the end endpoint must stay on the selection leading edge; the fill box '
          'reaches x = 0 and must not be chosen',
    );
  });

  test('control: under BoxWidthStyle.tight there is no extra box and both endpoints agree', () {
    final RenderEditable editable =
        _laidOut(_rtlText, _midLineWord, TextDirection.rtl, widthStyle: ui.BoxWidthStyle.tight);
    final List<ui.TextBox> boxes = editable.getBoxesForSelection(_midLineWord);
    expect(boxes.length, 1, reason: 'tight must not add a fill box');

    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_midLineWord);
    final Rect startCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.start));
    final Rect endCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.end));
    expect(endpoints.first.point.dx, closeTo(startCaret.center.dx, 3));
    expect(endpoints.last.point.dx, closeTo(endCaret.center.dx, 3));
  });

  test('control: the LTR mirror of the same selection is correct', () {
    final RenderEditable editable = _laidOut(_ltrText, _midLineWord, TextDirection.ltr);
    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_midLineWord);

    final Rect startCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.start));
    final Rect endCaret = editable.getLocalRectForCaret(TextPosition(offset: _midLineWord.end));
    expect(endpoints.first.point.dx, closeTo(startCaret.center.dx, 3));
    expect(endpoints.last.point.dx, closeTo(endCaret.center.dx, 3));
  });
}
