import 'package:flutter/material.dart';

/// Every colour the kit paints with, for one brightness.
///
/// The fields match Udyoga's `Palette` record (`lib/ui/look.dart`), so
/// Udyoga can move to the kit with no visual change. Each app installs its
/// own: Udyoga keeps azure, Vidya gets moss and clay.
///
/// ```dart
/// ThemeData(extensions: [udyogaLight]);
/// final p = KitPalette.of(context);
/// ```
@immutable
class KitPalette extends ThemeExtension<KitPalette> {
  const KitPalette({
    required this.top,
    required this.bottom,
    required this.glow,
    required this.glow2,
    required this.surface,
    required this.card,
    required this.subtle,
    required this.raised,
    required this.hairline,
    required this.text,
    required this.heading,
    required this.muted,
    required this.primary,
  });

  // The canvas behind every page: a vertical wash and two faint glows.
  final Color top;
  final Color bottom;
  final Color glow;
  final Color glow2;

  // Surfaces, from the page to quiet fills inside it.
  final Color surface;
  final Color card;
  final Color subtle;
  final Color raised;

  // Lines and text.
  final Color hairline;
  final Color text;
  final Color heading;
  final Color muted;
  final Color primary;

  /// The palette installed on the nearest theme. Throws a clear error when
  /// the app forgot to add one, rather than painting in a wrong colour.
  static KitPalette of(BuildContext context) {
    final p = Theme.of(context).extension<KitPalette>();
    assert(p != null, 'No KitPalette on the theme: add one to ThemeData.extensions.');
    return p!;
  }

  @override
  KitPalette copyWith({
    Color? top,
    Color? bottom,
    Color? glow,
    Color? glow2,
    Color? surface,
    Color? card,
    Color? subtle,
    Color? raised,
    Color? hairline,
    Color? text,
    Color? heading,
    Color? muted,
    Color? primary,
  }) => KitPalette(
    top: top ?? this.top,
    bottom: bottom ?? this.bottom,
    glow: glow ?? this.glow,
    glow2: glow2 ?? this.glow2,
    surface: surface ?? this.surface,
    card: card ?? this.card,
    subtle: subtle ?? this.subtle,
    raised: raised ?? this.raised,
    hairline: hairline ?? this.hairline,
    text: text ?? this.text,
    heading: heading ?? this.heading,
    muted: muted ?? this.muted,
    primary: primary ?? this.primary,
  );

  @override
  KitPalette lerp(KitPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return KitPalette(
      top: l(top, other.top),
      bottom: l(bottom, other.bottom),
      glow: l(glow, other.glow),
      glow2: l(glow2, other.glow2),
      surface: l(surface, other.surface),
      card: l(card, other.card),
      subtle: l(subtle, other.subtle),
      raised: l(raised, other.raised),
      hairline: l(hairline, other.hairline),
      text: l(text, other.text),
      heading: l(heading, other.heading),
      muted: l(muted, other.muted),
      primary: l(primary, other.primary),
    );
  }
}
