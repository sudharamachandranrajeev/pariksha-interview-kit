# Changelog

## 0.0.1 (unreleased)

- J1: motion and components moved here from Udyoga, palette-driven: `Ease`, `Pace`, `Radii`,
  `TypeScale`, `figures`, `RisePageTransitionsBuilder` (with an app-supplied canvas), `Backdrop`,
  `Tilt`, `TiltGrid`, `Headline`, `BlurFadeIn`, `BorderBeam`, `DotGrid`, `Glass`,
  `RollingNumber`, `showSheet`, `ShimmerSkeleton`, `SpotlightCard`, `StatGrid`, `StatusPill`,
  `showToast`, `KitShadBridge`.
- `KitPalette.of` falls back to a palette made from the theme's `ColorScheme`.
- Toast text colour is picked for contrast (`readableOn`), so it can never match the toast's
  background.
- J0 skeleton: `KitPalette` theme extension, `reducedMotion`, `KitStatus`.
