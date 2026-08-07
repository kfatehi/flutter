// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Regression test: the caret for the position at the end of a right-to-left line that ends in
// trailing whitespace used to be placed a fixed 0.75em to the left of where the whitespace
// actually is, because it anchored to the line terminator's zero-width box and the engine does not
// position that box reliably once the whitespace hangs outside the line.
//
// User-visible effect: typing a space at the end of a line of Farsi produced a gap several times
// wider than a space -- it read as a tab -- and typing one more character snapped it back.
//
// The paragraph is laid out with minWidth == maxWidth on purpose. With only maxWidth the painter
// collapses to its intrinsic width, the line's leading edge and the paragraph's edge coincide, and
// a caret placed at the wrong one of the two is indistinguishable from a correct caret.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const double _fontSize = 10.0;
const double _width = 200.0;

TextPainter _painter(String text, TextDirection direction) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: _fontSize)),
    textDirection: direction,
  );
  painter.layout(minWidth: _width, maxWidth: _width);
  return painter;
}

double _caretDx(TextPainter painter, int offset) =>
    painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dx;

/// How far the caret moves across the space at [spaceOffset].
double _spaceAdvance(TextPainter painter, int spaceOffset) =>
    (_caretDx(painter, spaceOffset) - _caretDx(painter, spaceOffset + 1)).abs();

void main() {
  test('RTL caret does not overshoot a trailing space at the end of a line', () {
    // 'سلام' is 4 code units, so the space is at 4 and the line terminator at 5.
    final TextPainter interior = _painter('سلام سلام', TextDirection.rtl);
    final TextPainter trailing = _painter('سلام \nحال', TextDirection.rtl);

    final double interiorSpace = _spaceAdvance(interior, 4);
    expect(interiorSpace, greaterThan(0.0));

    expect(
      _spaceAdvance(trailing, 4),
      interiorSpace,
      reason: 'a space at the end of a line must advance the caret by the same amount as the same '
          'space in the middle of a line',
    );
  });

  test('RTL caret at a line end is unaffected when there is no trailing space', () {
    // Guards the narrowness of the fix: with no trailing whitespace the terminator's box is
    // already correct and must still be what the caret uses.
    final TextPainter painter = _painter('سلام\nحال', TextDirection.rtl);
    final LineMetrics firstLine = painter.computeLineMetrics().first;
    expect(_caretDx(painter, 4), firstLine.left);
  });

  test('LTR trailing space at a line end is unchanged', () {
    final TextPainter interior = _painter('abcd abcd', TextDirection.ltr);
    final TextPainter trailing = _painter('abcd \nefg', TextDirection.ltr);
    expect(_spaceAdvance(trailing, 4), _spaceAdvance(interior, 4));
  });
}
