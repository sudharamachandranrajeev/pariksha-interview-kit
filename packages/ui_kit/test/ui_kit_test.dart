import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

// Udyoga's light palette (lib/ui/look.dart), as Udyoga will install it.
const _azure = KitPalette(
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

void main() {
  testWidgets('the app palette reaches widgets through the theme', (tester) async {
    late KitPalette seen;
    late bool reduced;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [_azure]),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              seen = KitPalette.of(context);
              reduced = reducedMotion(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(seen.primary, const Color(0xFF2E6AFE));
    expect(reduced, isTrue);
  });

  test('lerp and copyWith keep every field', () {
    final moss = _azure.copyWith(primary: const Color(0xFF5B7A4A));
    expect(moss.top, _azure.top);
    expect(_azure.lerp(moss, 1).primary, moss.primary);
    expect(_azure.lerp(null, 0.5), same(_azure));
    expect(KitStatus.values.map((s) => s.name), ['good', 'warning', 'serious', 'critical', 'info']);
  });
}
