import 'package:flutter/material.dart';

import 'motion.dart';
import 'palette.dart';

/// Press feedback for a card that opens something: it sinks a touch while
/// held, so the app is seen to have heard. Hover is left to the card's own
/// highlight ([SpotlightCard]). Still under reduced motion.
class Tilt extends StatefulWidget {
  const Tilt({super.key, required this.child});
  final Widget child;

  @override
  State<Tilt> createState() => _TiltState();
}

class _TiltState extends State<Tilt> {
  var _down = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return widget.child;
    return Listener(
      onPointerDown: (_) => _press(true),
      onPointerUp: (_) => _press(false),
      onPointerCancel: (_) => _press(false),
      child: AnimatedScale(
        scale: _down ? 0.98 : 1,
        duration: Pace.fast,
        curve: Ease.out,
        child: widget.child,
      ),
    );
  }
}

/// Tiles in a wrapping grid, each at least [minWidth] wide, that sink a
/// touch when pressed (see [Tilt]).
class TiltGrid extends StatelessWidget {
  const TiltGrid({super.key, required this.children, this.minWidth = 200});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: LayoutBuilder(
      builder: (context, c) {
        final cols = (c.maxWidth / minWidth).floor().clamp(1, children.isEmpty ? 1 : children.length);
        final w = (c.maxWidth - 12 * (cols - 1)) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(
                width: w,
                child: Tilt(child: child),
              ),
          ],
        );
      },
    ),
  );
}

/// A big greeting with one phrase picked out in the palette's primary.
class Headline extends StatelessWidget {
  const Headline(this.parts, {super.key});

  /// Alternating plain and highlighted runs, starting plain.
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final primary = KitPalette.of(context).primary;
    final base = t.headlineMedium?.copyWith(fontWeight: FontWeight.w500, height: 1.2);
    return Text.rich(
      TextSpan(
        children: [
          for (final (i, p) in parts.indexed)
            TextSpan(
              text: p,
              style: i.isOdd ? base?.copyWith(fontWeight: FontWeight.w800, color: primary) : base,
            ),
        ],
      ),
    );
  }
}
