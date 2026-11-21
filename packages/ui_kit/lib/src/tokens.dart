import 'package:flutter/painting.dart';

/// Corner radii: [sm] for inputs, buttons and small cards, [lg] for cards,
/// dialogs and sheets. Pills are fully round.
abstract final class Radii {
  static const sm = 12.0;
  static const lg = 16.0;
  static const pill = 999.0;
}

/// How strongly frosted glass (floating bars, sheets) blurs what is behind
/// it.
const glassBlur = 16.0;

/// The type scale, in logical pixels: 12, 14, 16, 20, 24, 30, 36.
abstract final class TypeScale {
  static const xs = 12.0;
  static const sm = 14.0;
  static const base = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 30.0;
  static const display = 36.0;
}

/// Figures that line up in columns and do not jiggle as they change: for
/// counts, money and dates. Merge it into any style that shows numbers.
const figures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
