# ui_kit

Shared motion and components for the Brahma apps. See the [repo README](../../README.md).

- Colours come in through `KitPalette`, a `ThemeExtension`, so each app keeps its own look.
  With no palette installed, the kit builds one from the theme's `ColorScheme`.
- Every animation stops when the system asks for reduced motion (`reducedMotion`, `paced`).
- No brahma_core and no native libraries.

## What's inside

| Part | What it does |
| --- | --- |
| `Ease`, `Pace`, `paced` | Motion curves and lengths (150, 200, 250 ms) |
| `Radii`, `TypeScale`, `figures`, `glassBlur` | Corner radii, type sizes, tabular figures, glass blur |
| `RisePageTransitionsBuilder` | Pushed pages rise and fade in, each on its own canvas |
| `Backdrop` | The page canvas: a wash and two faint glows, from the palette |
| `Tilt`, `TiltGrid` | Cards that sink a touch when pressed |
| `Headline` | A greeting with one phrase in the primary colour |
| `BlurFadeIn` | Items rise and come into focus once, staggered in a list |
| `SpotlightCard` | A card with a soft glow that follows the mouse |
| `StatGrid`, `StatCard`, `StatTile` | Even rows of number tiles |
| `RollingNumber` | Digits roll to a new value |
| `ShimmerSkeleton`, `SkeletonCards` | Loading placeholders |
| `Glass` | Frosted glass for things that float |
| `showSheet`, `KitSheet` | A bottom sheet that follows the finger |
| `showToast` | A short note at the bottom; its text always contrasts with its card |
| `StatusPill` | A small rounded label with a status dot |
| `DotGrid`, `BorderBeam` | A quiet dot pattern and a beam that runs round a border |
| `KitShadBridge` | The shadcn_ui theme `SpotlightCard` and `StatusPill` need, from the palette |
| `contrastRatio`, `readableOn` | WCAG contrast, and a text colour that reads on a background |

## Set up an app

1. Add a `KitPalette` for each brightness to `ThemeData.extensions`.
2. Use `RisePageTransitionsBuilder.everywhere(...)` in `pageTransitionsTheme`. Pass
   `backdrop:` if the app has its own canvas.
3. Wrap the app in `KitShadBridge` from `MaterialApp.builder`, unless it installs its own
   `ShadTheme`.
