import 'package:flutter/widgets.dart';

/// True when the platform asks for reduced motion. Every kit animation
/// checks this and settles at once instead.
///
/// The same one-liner as brahma_core's `Motion.reduced`, copied so the kit
/// does not depend on brahma_core.
bool reducedMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [d], or no time at all when the platform asks for reduced motion.
Duration paced(BuildContext context, Duration d) => reducedMotion(context) ? Duration.zero : d;

/// Motion curves, after Emil Kowalski's: [out] for things entering or
/// leaving, [inOut] for things moving on screen, [drawer] for sheets.
/// Nothing uses ease-in: it feels slow to start.
abstract final class Ease {
  static const out = Cubic(0.23, 1, 0.32, 1);
  static const inOut = Cubic(0.77, 0, 0.175, 1);
  static const drawer = Cubic(0.32, 0.72, 0, 1);
}

/// Motion lengths. Interface motion stays between 150 and 250 ms.
abstract final class Pace {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 250);
}
