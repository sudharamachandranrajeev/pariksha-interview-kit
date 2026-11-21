import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import 'support.dart';

/// Toast text must always read on the toast. The bug this guards: a toast
/// (a Material SnackBar at the time) whose text came out in the same dark
/// colour as its dark background, so its words vanished in dark mode.
void main() {
  // Vidya's moss and clay, light and dark.
  const mossLight = KitPalette(
    top: Color(0xFFF5F2EA),
    bottom: Color(0xFFEFEBDF),
    glow: Color(0x174F7C68),
    glow2: Color(0x17B5835A),
    surface: Color(0xFFFBF9F4),
    card: Color(0xFFFBF9F4),
    subtle: Color(0xFFEDE9DE),
    raised: Color(0xFFEDE9DE),
    hairline: Color(0xFFE2DDD0),
    text: Color(0xFF2B312D),
    heading: Color(0xFF2B312D),
    muted: Color(0xFF68716B),
    primary: Color(0xFF4F7C68),
  );
  final mossDark = mossLight.copyWith(
    top: const Color(0xFF111713),
    bottom: const Color(0xFF0C110E),
    surface: const Color(0xFF151C18),
    card: const Color(0xFF18211C),
    text: const Color(0xFFE7EAE4),
    heading: const Color(0xFFE7EAE4),
    muted: const Color(0xFFA3ADA6),
    primary: const Color(0xFF8DB9A2),
  );

  final palettes = <String, KitPalette>{
    'azure light': azureLight,
    'azure dark': azureDark,
    'moss light': mossLight,
    'moss dark': mossDark,
    'scheme light': KitPalette.fromScheme(ColorScheme.fromSeed(seedColor: Colors.teal)),
    'scheme dark': KitPalette.fromScheme(
      ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
    ),
    // The bug, recreated: a palette whose text is its background colour.
    'text = surface (dark)': azureDark.copyWith(text: azureDark.surface),
    'text = surface (light)': azureLight.copyWith(text: azureLight.surface),
  };

  for (final MapEntry(key: name, value: p) in palettes.entries) {
    test('toast text reads on its background: $name', () {
      for (final s in KitStatus.values) {
        final c = toastColors(p, s);
        expect(contrastRatio(c.background, c.foreground), greaterThanOrEqualTo(4.5));
      }
    });
  }

  test('a palette whose text already reads keeps its own text colour', () {
    expect(toastColors(azureDark, KitStatus.info).foreground, azureDark.text);
    expect(toastColors(azureLight, KitStatus.good).foreground, azureLight.text);
    expect(toastColors(azureLight, KitStatus.good).tone, KitStatus.good.color);
    expect(toastColors(azureLight, KitStatus.info).tone, azureLight.primary);
  });

  test('contrastRatio and readableOn', () {
    expect(contrastRatio(Colors.black, Colors.white), closeTo(21, 0.01));
    expect(contrastRatio(Colors.white, Colors.white), 1);
    expect(readableOn(Colors.black), const Color(0xFFF4F6FB));
    expect(readableOn(Colors.white), const Color(0xFF0B1020));
    expect(readableOn(Colors.white, preferred: Colors.white), const Color(0xFF0B1020));
  });

  for (final b in Brightness.values) {
    for (final reduced in [false, true]) {
      testWidgets('a shown toast paints readable text (${b.name}, reduced: $reduced)', (tester) async {
        await tester.pumpWidget(kitApp(const SizedBox(), brightness: b, reduced: reduced));
        final context = tester.element(find.byType(SizedBox).last);
        showToast(context, 'Saved the job', description: 'One more', status: KitStatus.good);
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        final title = find.text('Saved the job');
        expect(title, findsOneWidget);
        final shown = DefaultTextStyle.of(tester.element(title)).style
            .merge(tester.widget<Text>(title).style)
            .color!;
        final bg = azure(b).surface;
        expect(contrastRatio(bg, shown), greaterThanOrEqualTo(4.5));
        if (reduced) expect(tester.binding.transientCallbackCount, 0);
        // It closes by itself.
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Saved the job'), findsNothing);
      });
    }
  }
}
