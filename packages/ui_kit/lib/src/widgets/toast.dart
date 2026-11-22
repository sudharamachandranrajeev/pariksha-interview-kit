import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import '../contrast.dart';
import '../motion.dart';
import '../palette.dart';
import '../status.dart';
import '../tokens.dart';

/// The colours a toast paints with: its card, its text and its tone (the
/// icon). The text is the palette's own text colour whenever that reads on
/// the card (4.5:1, WCAG AA), and near-black or near-white otherwise, so a
/// toast's words can never take the colour of its background.
typedef ToastColors = ({Color background, Color foreground, Color tone});

/// The [ToastColors] for [status] on palette [p].
ToastColors toastColors(KitPalette p, KitStatus status) {
  final background = p.surface;
  return (
    background: background,
    foreground: readableOn(background, preferred: p.text),
    tone: status == KitStatus.info ? p.primary : status.color,
  );
}

/// Shows a short note at the bottom of the screen, after Sonner: it slides
/// up, stays four seconds (longer when hovered), and can be swiped away.
/// [status] picks its icon and colour; under reduced motion it just appears.
ToastificationItem showToast(
  BuildContext context,
  String title, {
  String? description,
  KitStatus status = KitStatus.info,
  Duration stay = const Duration(seconds: 4),
}) {
  final p = KitPalette.of(context);
  final c = toastColors(p, status);
  return toastification.show(
    context: context,
    // The text colour is set here as well as through foregroundColor, so a
    // theme's text style can never paint it in the background's colour.
    title: Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: c.foreground),
    ),
    description: description == null
        ? null
        : Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.foreground.withValues(alpha: 0.8)),
          ),
    icon: Icon(status.icon, color: c.tone),
    type: switch (status) {
      KitStatus.good => ToastificationType.success,
      KitStatus.warning => ToastificationType.warning,
      KitStatus.serious || KitStatus.critical => ToastificationType.error,
      KitStatus.info => ToastificationType.info,
    },
    style: ToastificationStyle.flat,
    alignment: Alignment.bottomCenter,
    autoCloseDuration: stay,
    // Toasts are the exception to the 250 ms rule: Sonner's 400 ms.
    animationDuration: paced(context, const Duration(milliseconds: 400)),
    primaryColor: c.tone,
    backgroundColor: c.background,
    foregroundColor: c.foreground,
    borderRadius: BorderRadius.circular(Radii.sm),
    borderSide: BorderSide(color: p.hairline),
    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4))],
    showProgressBar: false,
    dragToClose: true,
    pauseOnHover: true,
    closeButton: const ToastCloseButton(showType: CloseButtonShowType.onHover),
  );
}

/// Closes every toast at once, without the exit animation: on sign-out, or
/// at the end of a widget test, where a toast's close timer would otherwise
/// still be pending.
void dismissAllToasts() => toastification.dismissAll(delayForAnimation: false);
