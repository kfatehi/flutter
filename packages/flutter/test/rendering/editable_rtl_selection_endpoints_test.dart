// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression tests for RenderEditable.getEndpointsForSelection in right-to-left text.
//
// getEndpointsForSelection derives the selection's two endpoints positionally:
//
//   start = boxes.first.start    end = boxes.last.end
//
// and ui.TextBox.start/end are direction-aware (start => ltr ? left : right). That is correct
// only when boxes.first holds the selection's logical start and boxes.last its logical end.
// When one line of right-to-left text produces more than one selection box, the boxes come back
// ordered left-to-right on screen, so for RTL boxes.first holds the logical END. Both endpoints
// then land on the inner edges of the boundary boxes instead of the selection's outer edges.
//
// The endpoints are also the positions the selection handles are painted at
// (RenderEditable._paintHandleLayers), so this draws both handles inside the selection and binds
// the handle that owns `base` to the visually opposite side of it.
//
// Everything here uses the test font: the several boxes come from differing style runs, not from
// shaping, so no font asset is required.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

// Three runs of right-to-left text. Differing fontWeight puts them in separate style runs, which
// is what makes the line produce more than one selection box.
const String _run1 = 'خانه '; // logically first -> drawn RIGHTmost in RTL
const String _run2 = 'نشسته ';
const String _run3 = 'ام'; // logically last  -> drawn LEFTmost in RTL

const TextSpan _multiRunRtlSpan = TextSpan(
  style: TextStyle(fontSize: 16),
  children: <InlineSpan>[
    TextSpan(text: _run1, style: TextStyle(fontWeight: FontWeight.w400)),
    TextSpan(text: _run2, style: TextStyle(fontWeight: FontWeight.w900)),
    TextSpan(text: _run3, style: TextStyle(fontWeight: FontWeight.w400)),
  ],
);

const int _fullLength = 13; // _run1.length + _run2.length + _run3.length
const TextSelection _fullSelection = TextSelection(baseOffset: 0, extentOffset: _fullLength);

const double _viewportWidth = 500;

RenderEditable _editable(TextSpan text, TextSelection selection, TextDirection direction) {
  return RenderEditable(
    text: text,
    textDirection: direction,
    startHandleLayerLink: LayerLink(),
    endHandleLayerLink: LayerLink(),
    offset: ViewportOffset.zero(),
    textSelectionDelegate: _FakeEditableTextState(),
    selection: selection,
  );
}

RenderEditable _laidOut(TextSpan text, TextSelection selection, TextDirection direction) {
  final RenderEditable editable = _editable(text, selection, direction);
  layout(editable, constraints: const BoxConstraints(maxWidth: _viewportWidth));
  return editable;
}

double _leftmost(List<ui.TextBox> boxes) =>
    boxes.map((ui.TextBox b) => b.left).reduce((double a, double b) => a < b ? a : b);

double _rightmost(List<ui.TextBox> boxes) =>
    boxes.map((ui.TextBox b) => b.right).reduce((double a, double b) => a > b ? a : b);

void main() {
  TestRenderingFlutterBinding.ensureInitialized();

  test('setup guard: the RTL selection really does span several boxes on one line', () {
    final RenderEditable editable = _laidOut(_multiRunRtlSpan, _fullSelection, TextDirection.rtl);
    final List<ui.TextBox> boxes = editable.getBoxesForSelection(_fullSelection);

    // If any of this fails, the rest of the file is not testing what it claims to.
    expect(boxes.length, greaterThan(1), reason: 'the selection must span several boxes');
    expect(
      boxes.every((ui.TextBox box) => box.top == boxes.first.top),
      isTrue,
      reason: 'all boxes must be on ONE line; multi-line selection is a different code path',
    );
    expect(
      boxes.every((ui.TextBox box) => box.direction == TextDirection.rtl),
      isTrue,
      reason: 'this is a pure RTL selection; no box may be bidi-flipped',
    );
  });

  test('RTL selection endpoints are the visual extremes of the selection', () {
    final RenderEditable editable = _laidOut(_multiRunRtlSpan, _fullSelection, TextDirection.rtl);
    final List<ui.TextBox> boxes = editable.getBoxesForSelection(_fullSelection);
    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_fullSelection);

    expect(endpoints.length, 2);
    // In RTL the logical start is the selection's right-hand edge and the logical end its
    // left-hand edge.
    expect(
      endpoints.first.point.dx,
      _rightmost(boxes),
      reason: 'the start endpoint must sit on the RIGHT edge of an RTL selection',
    );
    expect(
      endpoints.last.point.dx,
      _leftmost(boxes),
      reason: 'the end endpoint must sit on the LEFT edge of an RTL selection',
    );
  });

  test('each RTL endpoint sits where the caret for its own offset sits', () {
    final RenderEditable editable = _laidOut(_multiRunRtlSpan, _fullSelection, TextDirection.rtl);
    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_fullSelection);

    // A selection handle points at the position its endpoint would put the caret at. If it does
    // not, dragging that handle moves an endpoint the user did not grab.
    final Rect baseCaret =
        editable.getLocalRectForCaret(TextPosition(offset: _fullSelection.baseOffset));
    final Rect extentCaret =
        editable.getLocalRectForCaret(TextPosition(offset: _fullSelection.extentOffset));

    expect(
      endpoints.first.point.dx,
      closeTo(baseCaret.center.dx, 2),
      reason: 'the start endpoint must coincide with the caret at baseOffset',
    );
    expect(
      endpoints.last.point.dx,
      closeTo(extentCaret.center.dx, 2),
      reason: 'the end endpoint must coincide with the caret at extentOffset',
    );
  });

  test('RTL selection endpoints bracket every selection box', () {
    final RenderEditable editable = _laidOut(_multiRunRtlSpan, _fullSelection, TextDirection.rtl);
    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(_fullSelection);

    final double lo = math.min(endpoints.first.point.dx, endpoints.last.point.dx);
    final double hi = math.max(endpoints.first.point.dx, endpoints.last.point.dx);

    // No part of the highlighted selection may fall outside the two handles.
    for (final ui.TextBox box in editable.getBoxesForSelection(_fullSelection)) {
      expect(
        box.left,
        greaterThanOrEqualTo(lo),
        reason: 'a selection box extends to the left of both endpoints',
      );
      expect(
        box.right,
        lessThanOrEqualTo(hi),
        reason: 'a selection box extends to the right of both endpoints',
      );
    }
  });

  test('control: a single-box RTL selection already has correct endpoints', () {
    // Selecting within one style run yields one box, and today's code gets that right. This is
    // why the defect stays invisible until the selection crosses a run boundary.
    const TextSelection selection = TextSelection(baseOffset: 0, extentOffset: 4);
    final RenderEditable editable = _laidOut(_multiRunRtlSpan, selection, TextDirection.rtl);

    final List<ui.TextBox> boxes = editable.getBoxesForSelection(selection);
    expect(boxes.length, 1);

    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(selection);
    expect(endpoints.first.point.dx, boxes.single.right);
    expect(endpoints.last.point.dx, boxes.single.left);
  });

  test('control: an LTR multi-box selection has correct endpoints', () {
    const TextSpan ltrSpan = TextSpan(
      style: TextStyle(fontSize: 16),
      children: <InlineSpan>[
        TextSpan(text: 'one ', style: TextStyle(fontWeight: FontWeight.w400)),
        TextSpan(text: 'two ', style: TextStyle(fontWeight: FontWeight.w900)),
        TextSpan(text: 'six', style: TextStyle(fontWeight: FontWeight.w400)),
      ],
    );
    const TextSelection selection = TextSelection(baseOffset: 0, extentOffset: 11);
    final RenderEditable editable = _laidOut(ltrSpan, selection, TextDirection.ltr);

    final List<ui.TextBox> boxes = editable.getBoxesForSelection(selection);
    expect(boxes.length, greaterThan(1));

    final List<TextSelectionPoint> endpoints = editable.getEndpointsForSelection(selection);
    // For LTR visual and logical order agree, so the existing code is correct.
    expect(endpoints.first.point.dx, _leftmost(boxes));
    expect(endpoints.last.point.dx, _rightmost(boxes));
  });
}
