import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The WCAG contrast ratio between two opaque colours, from 1 (the same)
/// to 21 (black on white). Transparency is ignored: blend first.
double contrastRatio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// [preferred] when it reads on [background] at [minRatio] or better (WCAG
/// AA for body text is 4.5); otherwise near-black or near-white, whichever
/// reads better. Text drawn with this can never vanish into its background.
Color readableOn(
  Color background, {
  Color? preferred,
  double minRatio = 4.5,
  Color dark = const Color(0xFF0B1020),
  Color light = const Color(0xFFF4F6FB),
}) {
  final bg = background.withValues(alpha: 1);
  if (preferred != null && contrastRatio(bg, preferred.withValues(alpha: 1)) >= minRatio) return preferred;
  return contrastRatio(bg, dark) >= contrastRatio(bg, light) ? dark : light;
}
