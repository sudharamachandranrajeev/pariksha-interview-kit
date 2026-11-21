import 'package:flutter/material.dart';

/// How good or bad something is, for pills, stat tiles and toasts.
///
/// Mirrors brahma_core's `Status` (same values, colours and icons) so the
/// kit needs no brahma_core. Apps that use brahma_core map one to the other
/// by name: `KitStatus.values.byName(status.name)`.
enum KitStatus {
  good(Color(0xFF0CA30C), Icons.check_circle_outline),
  warning(Color(0xFFFAB219), Icons.warning_amber_rounded),
  serious(Color(0xFFEC835A), Icons.report_outlined),
  critical(Color(0xFFD03B3B), Icons.error_outline),
  info(null, Icons.info_outline);

  const KitStatus(this._color, this.icon);
  final Color? _color;
  final IconData icon;

  /// The status colour; [info] is a neutral grey.
  Color get color => _color ?? const Color(0xFF898781);
}
