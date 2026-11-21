import 'package:flutter/material.dart';

import 'motion.dart';
import 'palette.dart';

/// The canvas: a soft vertical wash with two faint glows, behind every page.
/// Colours come from the [KitPalette] (`top`, `bottom`, `glow`, `glow2`).
class Backdrop extends StatelessWidget {
  const Backdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = KitPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.top, p.bottom],
          stops: const [0, 0.55],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -160, right: -120, child: Glow(p.glow, 420)),
          Positioned(bottom: -200, left: -160, child: Glow(p.glow2, 460)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// A soft round glow, fading from [color] at the centre to nothing.
class Glow extends StatelessWidget {
  const Glow(this.color, this.size, {super.key});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    ),
  );
}

/// Wraps a page in the kit's [Backdrop]: the default for
/// [RisePageTransitionsBuilder].
Widget kitBackdrop(Widget child) => Backdrop(child: child);

/// Pushed pages rise a little into place and fade in, while the page
/// underneath dims slightly. A page opens tens of times a day, so it is short
/// (250 ms) and leaves at once: the way back starts fast. Under reduced
/// motion only a fade remains.
///
/// Each page brings its own canvas ([backdrop]), so the page beneath never
/// shows through a transparent scaffold. An app with its own canvas passes
/// it; `null` adds none.
class RisePageTransitionsBuilder extends PageTransitionsBuilder {
  const RisePageTransitionsBuilder({this.backdrop = kitBackdrop});

  /// Wraps each page in the app's canvas.
  final Widget Function(Widget child)? backdrop;

  /// The same builder for every platform, for `PageTransitionsTheme`.
  static Map<TargetPlatform, PageTransitionsBuilder> everywhere([
    RisePageTransitionsBuilder builder = const RisePageTransitionsBuilder(),
  ]) => {for (final p in TargetPlatform.values) p: builder};

  @override
  Duration get transitionDuration => Pace.slow;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final wrap = backdrop;
    if (wrap != null) child = wrap(child);
    // Under reduced motion a fade remains: it moves nothing.
    if (reducedMotion(context)) return FadeTransition(opacity: animation, child: child);
    final inCurve = CurvedAnimation(parent: animation, curve: Ease.out, reverseCurve: Ease.out.flipped);
    final outCurve = CurvedAnimation(parent: secondaryAnimation, curve: Ease.out);
    return AnimatedBuilder(
      animation: Listenable.merge([inCurve, outCurve]),
      child: child,
      builder: (context, child) => Opacity(
        opacity: (inCurve.value.clamp(0, 1) * (1 - outCurve.value * 0.2)).toDouble(),
        child: Transform.translate(offset: Offset(0, (1 - inCurve.value) * 24), child: child),
      ),
    );
  }
}
