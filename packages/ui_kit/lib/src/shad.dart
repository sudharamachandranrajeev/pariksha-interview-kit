import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart'
    show
        ShadColorScheme,
        ShadMouseAreaSurface,
        ShadMouseCursorProvider,
        ShadTextTheme,
        ShadTheme,
        ShadThemeData;

import 'contrast.dart';
import 'palette.dart';
import 'tokens.dart';

/// The palette for the shadcn_ui widgets the kit builds on ([SpotlightCard]
/// and [StatusPill] use `ShadCard` and `ShadBadge`), so they sit beside the
/// Material ones without a seam. [primaryForeground] defaults to whichever
/// of near-black and near-white reads on the primary.
ShadThemeData kitShadTheme(
  KitPalette p,
  Brightness b, {
  String? fontFamily,
  Color? primaryForeground,
  Color destructive = const Color(0xFFE5484D),
}) => ShadThemeData(
  brightness: b,
  radius: BorderRadius.circular(Radii.sm),
  textTheme: fontFamily == null ? null : ShadTextTheme(family: fontFamily),
  colorScheme: ShadColorScheme(
    background: p.surface,
    foreground: p.text,
    card: p.card,
    cardForeground: p.text,
    popover: p.surface,
    popoverForeground: p.text,
    primary: p.primary,
    primaryForeground: primaryForeground ?? readableOn(p.primary, preferred: Colors.white),
    secondary: p.subtle,
    secondaryForeground: p.text,
    muted: p.subtle,
    mutedForeground: p.muted,
    accent: p.raised,
    accentForeground: p.text,
    destructive: destructive,
    destructiveForeground: Colors.white,
    border: p.hairline,
    input: p.hairline,
    ring: p.primary,
    selection: p.primary.withValues(alpha: 0.3),
  ),
);

/// Puts the shadcn_ui theme (from the nearest [KitPalette], following the
/// Material theme's brightness) and the pointer services its widgets need
/// inside a MaterialApp, from the app's `builder`. Apps that already
/// install their own ShadTheme do not need it.
class KitShadBridge extends StatelessWidget {
  const KitShadBridge({super.key, required this.child, this.fontFamily, this.primaryForeground});
  final Widget child;
  final String? fontFamily;
  final Color? primaryForeground;

  @override
  Widget build(BuildContext context) => ShadTheme(
    data: kitShadTheme(
      KitPalette.of(context),
      Theme.of(context).brightness,
      fontFamily: fontFamily,
      primaryForeground: primaryForeground,
    ),
    child: ShadMouseAreaSurface(child: ShadMouseCursorProvider(child: child)),
  );
}
