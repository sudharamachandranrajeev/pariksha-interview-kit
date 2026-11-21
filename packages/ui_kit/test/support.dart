import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

// Udyoga's palettes (lib/ui/look.dart), as Udyoga installs them.
const azureLight = KitPalette(
  top: Color(0xFFE3EBFD),
  bottom: Color(0xFFF8FAFD),
  glow: Color(0x592F6BFF),
  glow2: Color(0x2E12B886),
  surface: Color(0xFFFFFFFF),
  card: Color(0xFFFFFFFF),
  subtle: Color(0xFFF2F5FA),
  raised: Color(0xFFEDF1F8),
  hairline: Color(0xFFE2E8F2),
  text: Color(0xFF0B1020),
  heading: Color(0xFF0B1020),
  muted: Color(0xFF586379),
  primary: Color(0xFF2E6AFE),
);

const azureDark = KitPalette(
  top: Color(0xFF0A1022),
  bottom: Color(0xFF05070F),
  glow: Color(0x4D2F6BFF),
  glow2: Color(0x2B12B886),
  surface: Color(0xFF0E1426),
  card: Color(0xFF111A2E),
  subtle: Color(0xFF151F37),
  raised: Color(0xFF1A2440),
  hairline: Color(0x17FFFFFF),
  text: Color(0xFFE8ECF6),
  heading: Color(0xFFFFFFFF),
  muted: Color(0xFF98A2B8),
  primary: Color(0xFF6E9BFF),
);

KitPalette azure(Brightness b) => b == Brightness.dark ? azureDark : azureLight;

/// A test app: the azure palette for [brightness] (or none, to test the
/// ColorScheme fallback), the shadcn bridge the kit's cards need, and
/// reduced motion when asked.
Widget kitApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool reduced = false,
  bool palette = true,
}) => MaterialApp(
  theme: ThemeData(
    brightness: brightness,
    colorSchemeSeed: const Color(0xFF2E6AFE),
    extensions: [if (palette) azure(brightness)],
  ),
  builder: (context, child) => KitShadBridge(
    child: MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
  ),
  home: Scaffold(body: Center(child: child)),
);
