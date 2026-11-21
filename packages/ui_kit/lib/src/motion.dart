import 'package:flutter/widgets.dart';

/// True when the platform asks for reduced motion. Every kit animation
/// checks this and settles at once instead.
///
/// The same one-liner as brahma_core's `Motion.reduced`, copied so the kit
/// does not depend on brahma_core.
bool reducedMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// [d], or no time at all when the platform asks for reduced motion.
Duration paced(BuildContext context, Duration d) => reducedMotion(context) ? Duration.zero : d;
