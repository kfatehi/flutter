// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression tests for RenderEditable.getEndpointsForSelection when a right-to-left
// selection spans MORE THAN ONE LINE.
//
// The sibling file editable_rtl_selection_endpoints_test.dart covers a selection
// that lives on a single line: there the boxes come back in visual (left-to-right)
// order, so reading boxes.first/boxes.last positionally puts both endpoints on the
// inner edges of the selection. The fix for that picks, within the first and last
// LINE, the box that holds the logical start and the one that holds the logical
// end — which means it first has to decide which boxes belong to which line.
//
// It groups them by VERTICAL OVERLAP, because under BoxHeightStyle.tight (what
// EditableText asks for) each box is only as tall as its own run, and a run that
// falls back to a different font reports a different top on the very same line.
// Comparing tops for equality would end the line after one box.
//
// Vertical overlap is not a safe substitute, because a box is NOT confined to its
// own line. EditableText passes StrutStyle.fromTextStyle(style, forceStrutHeight:
// true) whenever strutStyle is null — the default, and what the Bubbles apps use —
// which pins every line's advance to the PRIMARY font's height. A run that shapes
// from a taller fallback font produces a box taller than that advance, so it
// overhangs into the neighbouring line's band. Overlap grouping then merges the two
// lines and both endpoints are chosen out of the wrong one: the start endpoint gets
// the LAST line's y and the end endpoint gets the FIRST line's, with an x taken from
// the wrong line entirely.
//
// Measured on the device font pair (SysFont primary + Noto Naskh fallback, the
// OnePlus's own `sans-serif` and its Arabic fallback): line 0's word box is
// y=-0.80..33.26 while line 1's boxes start at y=25.20 — a 7.6px overhang, enough to
// collapse all 22 boxes of a two-line selection into a single group.
//
// No font asset is needed here. The trigger is the GEOMETRY — a box taller than the
// line advance — and an explicit strut smaller than the text reproduces it exactly
// with the test font, the same way differing fontSize reproduces the fallback
// geometry in the single-line suite.

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

// Wide enough to need two lines at _viewportWidth, in RTL.
const String _rtlText = 'خانه نشسته ام خانه نشسته ام خانه نشسته ام';
const String _ltrText = 'one two six one two six one two six one two';

const double _fontSize = 16;
const double _viewportWidth = 220;

// EditableText forces the strut height by default. A strut shorter than the text is
// the device situation in miniature: the line advances at the primary font's height
// while a taller run's box overhangs into the next line's band.
const StrutStyle _shortStrut = StrutStyle(fontSize: _fontSize * 0.75, forceStrutHeight: true);

RenderEditable _laidOut(String text, TextSelection selection, TextDirection direction) {
  final editable = RenderEditable(
    text: TextSpan(text: text, style: const TextStyle(fontSize: _fontSize)),
    textDirection: direction,
    startHandleLayerLink: LayerLink(),
    endHandleLayerLink: LayerLink(),
    offset: ViewportOffset.zero(),
    textSelectionDelegate: _FakeEditableTextState(),
    selection: selection,
    strutStyle: _shortStrut,
    maxLines: null,
    // Asked for explicitly. RenderEditable defaults this to BoxHeightStyle.max, which
    // stretches every box to its own line's band and therefore cannot express a box that
    // overhangs one. `tight` is what EditableText requests, and it is the style under
    // which a run reports the height it actually shaped at.
    selectionHeightStyle: ui.BoxHeightStyle.tight,
  );
  layout(editable, constraints: const BoxConstraints(maxWidth: _viewportWidth));
  return editable;
}

/// The selection used throughout: from the very start of the text to a point well
/// inside the second line, so its two endpoints must land on different lines.
TextSelection _twoLineSelection(RenderEditable editable, String text) {
  final Rect first = editable.getLocalRectForCaret(const TextPosition(offset: 0));
  for (var offset = 1; offset <= text.length; offset++) {
    final Rect r = editable.getLocalRectForCaret(TextPosition(offset: offset));
    if (r.top > first.top + 1) {
      // The first offset on the second line; take a few more so the selection has
      // real width there.
      return TextSelection(baseOffset: 0, extentOffset: (offset + 3).clamp(0, text.length));
    }
  }
  fail('the text did not wrap at width $_viewportWidth — widen the text or narrow the viewport');
}

void main() {
  TestRenderingFlutterBinding.ensureInitialized();

  test('setup guard: the RTL selection spans two lines whose boxes vertically overlap', () {
    RenderEditable editable = _laidOut(_rtlText, const TextSelection.collapsed(offset: 0), TextDirection.rtl);
    final TextSelection selection = _twoLineSelection(editable, _rtlText);
    editable = _laidOut(_rtlText, selection, TextDirection.rtl);

    final List<ui.TextBox> boxes = editable.getBoxesForSelection(selection);
    expect(boxes.length, greaterThan(1));

    final double firstTop = boxes.first.top;
    final List<ui.TextBox> lower =
        boxes.where((ui.TextBox b) => b.top > firstTop + 1).toList();
    expect(lower, isNotEmpty, reason: 'the selection must reach a second line');

    // The trigger: a first-line box reaches DOWN past the top of a second-line box.
    final double firstLineBottom = boxes
        .where((ui.TextBox b) => b.top <= firstTop + 1)
        .map((ui.TextBox b) => b.bottom)
        .reduce((double a, double b) => a > b ? a : b);
    final double secondLineTop =
        lower.map((ui.TextBox b) => b.top).reduce((double a, double b) => a < b ? a : b);
    expect(
      firstLineBottom,
      greaterThan(secondLineTop),
      reason: "this suite only tests something if the two lines' boxes overlap vertically",
    );
  });

  test('a multi-line RTL selection puts each endpoint on its own line', () {
    RenderEditable editable = _laidOut(_rtlText, const TextSelection.collapsed(offset: 0), TextDirection.rtl);
    final TextSelection selection = _twoLineSelection(editable, _rtlText);
    editable = _laidOut(_rtlText, selection, TextDirection.rtl);

    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(selection);
    expect(endpoints.length, 2);

    final Rect baseCaret = editable.getLocalRectForCaret(TextPosition(offset: selection.baseOffset));
    final Rect extentCaret =
        editable.getLocalRectForCaret(TextPosition(offset: selection.extentOffset));
    expect(extentCaret.top, greaterThan(baseCaret.top),
        reason: 'guard: the two offsets really are on different lines');

    // A handle is painted at its endpoint. If the start endpoint carries the LAST
    // line's y, the handle for `base` is drawn a line below the text it marks.
    expect(
      endpoints.first.point.dy,
      lessThan(endpoints.last.point.dy),
      reason: 'the start endpoint must sit on an EARLIER line than the end endpoint',
    );
  });

  test('each multi-line RTL endpoint sits where the caret for its own offset sits', () {
    RenderEditable editable = _laidOut(_rtlText, const TextSelection.collapsed(offset: 0), TextDirection.rtl);
    final TextSelection selection = _twoLineSelection(editable, _rtlText);
    editable = _laidOut(_rtlText, selection, TextDirection.rtl);

    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(selection);
    final Rect baseCaret = editable.getLocalRectForCaret(TextPosition(offset: selection.baseOffset));
    final Rect extentCaret =
        editable.getLocalRectForCaret(TextPosition(offset: selection.extentOffset));

    expect(
      endpoints.first.point.dx,
      closeTo(baseCaret.center.dx, 3),
      reason: 'the start endpoint must coincide with the caret at baseOffset',
    );
    expect(
      endpoints.last.point.dx,
      closeTo(extentCaret.center.dx, 3),
      reason: 'the end endpoint must coincide with the caret at extentOffset',
    );
  });

  test('control: the LTR mirror of the same selection is correct', () {
    RenderEditable editable = _laidOut(_ltrText, const TextSelection.collapsed(offset: 0), TextDirection.ltr);
    final TextSelection selection = _twoLineSelection(editable, _ltrText);
    editable = _laidOut(_ltrText, selection, TextDirection.ltr);

    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(selection);
    final Rect baseCaret = editable.getLocalRectForCaret(TextPosition(offset: selection.baseOffset));
    final Rect extentCaret =
        editable.getLocalRectForCaret(TextPosition(offset: selection.extentOffset));

    expect(endpoints.first.point.dy, lessThan(endpoints.last.point.dy));
    expect(endpoints.first.point.dx, closeTo(baseCaret.center.dx, 3));
    expect(endpoints.last.point.dx, closeTo(extentCaret.center.dx, 3));
  });
}
