# Foundations

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `the-reset`, `logical-properties`, `oklch-color`,
`one-set-of-color-tokens-for-light-and-dark`, `fluid-sizes-with-clamp`,
`one-fluid-scale-for-type-and-space`.

## The reset: `the-reset`

Why: one base stylesheet removes the layout, font and touch defaults that every later rule fights.

Baseline: [`text-wrap`](https://developer.mozilla.org/en-US/docs/Web/CSS/text-wrap#browser_compatibility),
[`scrollbar-gutter`](https://developer.mozilla.org/en-US/docs/Web/CSS/scrollbar-gutter#browser_compatibility),
[`interpolate-size`](https://developer.mozilla.org/en-US/docs/Web/CSS/interpolate-size#browser_compatibility);
the rest is widely available. As of 2026-10-11, recheck on a status change.

Start a new project with it. In an existing project add one rule at a time and look at the result:
`min-width: 0` and the font rules change how things already render.

```css
*,
*::before,
*::after {
  box-sizing: border-box;
  min-width: 0;
}

:root {
  interpolate-size: allow-keywords;
  scrollbar-gutter: stable;
  text-wrap: pretty;
  overflow-wrap: break-word;
  font-synthesis: none;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  -webkit-text-size-adjust: 100%;
  -webkit-tap-highlight-color: transparent;
}

body {
  margin: 0;
  min-height: 100svh;
}

h1, h2, h3, h4 { text-wrap: balance; }

img, svg, video {
  display: block;
  max-width: 100%;
  height: auto;
}

input, textarea, select { font-size: max(16px, 1rem); }

button, a, [role="button"] { touch-action: manipulation; }

button, [role="button"] {
  user-select: none;
  -webkit-user-select: none;
}
```

Rules:

- Load every weight and style the design uses. With `font-synthesis: none` a missing bold renders
  as regular.
- With `min-width: 0` on everything, a sized image, icon or avatar in a flex row shrinks for the
  text beside it. Give it `flex: none`.
- The reset removes the tap highlight, so every pressable element needs its own `:active` state:
  `press-feedback` (`interaction.md`).
- Never fix input zoom with `user-scalable=no` or `maximum-scale=1`; that takes zoom from people
  who need it.
- Keep `user-select: none` to controls, never on `body` or links: people copy text.
- Typed text inherits `pretty` in `textarea` and `contenteditable`. If lines shift while typing,
  set `text-wrap: stable` on that element.
- The reserved gutter puts centered content slightly off-center on a page too short to scroll.
  Accept it.
- `svh` is for documents and heroes. An app shell with UI pinned to the bottom uses
  `height: 100dvh`, so it tracks the browser toolbar.

## Logical properties: `logical-properties`

Why: inline and block sides follow writing direction, so one rule serves left-to-right,
right-to-left and vertical text.

Baseline: [`margin-inline`](https://developer.mozilla.org/en-US/docs/Web/CSS/margin-inline#browser_compatibility),
[`inset-inline`](https://developer.mozilla.org/en-US/docs/Web/CSS/inset-inline#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use them in place of every left, right, top and bottom: spacing, borders, offsets, alignment.

```css
.card {
  position: relative;
  padding-inline: var(--space-m, 1.5rem);
  margin-block-end: var(--space-l, 2rem);
  border-inline-start: 4px solid;
  text-align: start;
}

.card .close {
  position: absolute;
  inset-block-start: 1rem;
  inset-inline-end: 1rem;
}
```

Rules:

- The four-value `margin`, `padding` and `inset` shorthands stay physical. Use the `-inline` and
  `-block` shorthands.

## OKLCH color: `oklch-color`

Why: OKLCH is perceptually even, so mixes and tints derived from one base stay on hue and
lightness steps look equal.

Baseline: [`oklch()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/oklch#browser_compatibility),
[`color-mix()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/color-mix#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Write colors in `oklch()` and derive every related color from a base with
`color-mix(in oklch, …)`. Never hardcode a second hex or `rgba()` for a hover, tint or transparent
version.

```css
:root {
  --primary-hover: color-mix(in oklch, var(--primary), black 15%);
  --primary-subtle: color-mix(in oklch, var(--primary) 12%, transparent);
}
```

`--primary` is the project's base color token, written as `oklch(L C H)` where the project
controls the format.

Rules:

- Write grays, white and black with `none` as the hue, as in `oklch(98% 0 none)`. A written hue of
  `0` is red and pulls every mix toward red; with `none`, or the keyword `white`, a mix keeps the
  other color's hue.

## One set of color tokens for light and dark: `one-set-of-color-tokens-for-light-and-dark`

Why: each token holds both values, so there is no second variable block under a media query or a
`.dark` class to drift out of sync.

Baseline: [`light-dark()`](https://developer.mozilla.org/en-US/docs/Web/CSS/color_value/light-dark#browser_compatibility).
As of 2026-10-11, recheck on a status change.

```css
:root {
  color-scheme: light dark;
  --background: light-dark(var(--background-light), var(--background-dark));
  --foreground: light-dark(var(--foreground-light), var(--foreground-dark));
}

[data-theme="light"] { color-scheme: light; }
[data-theme="dark"] { color-scheme: dark; }
```

Rules:

- Switch themes by setting `color-scheme`. Never redefine the tokens.
- Grays use `none` for the hue so they mix without drifting toward red (`oklch-color`).
- `light-dark()` takes two colors. Anything else that differs by theme, such as an image, needs
  its own rule.
- Add `<meta name="color-scheme" content="light dark">` so the browser paints the right background
  before the CSS loads.

## Fluid sizes with `clamp()`: `fluid-sizes-with-clamp`

Why: one declaration that grows with the screen replaces a ladder of breakpoint overrides.

Baseline: [`clamp()`](https://developer.mozilla.org/en-US/docs/Web/CSS/clamp#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for anything that should grow with the screen, starting with font sizes and section
spacing.

```css
:root {
  --text-body: clamp(1rem, 0.75rem + 1vw, 1.75rem);
  --space-section: clamp(3rem, 1rem + 6vw, 8rem);
}
```

Rules:

- Write the preferred value as `rem + vw`, never `vw` alone. `clamp(1rem, 1vw, 1.75rem)` stays at
  16px on every screen narrower than 1600px, and a bare `vw` ignores the reader's font size.
- Work the preferred value out from two points. The slope is `(max - min) / (wide - narrow)` in px
  over px; times 100 it is the `vw` number. The `rem` part is `min - slope × narrow`.
- Keep both bounds in `rem` so they follow the reader's font size.
- For a font size, keep the maximum at or below 2.5 times the minimum. The `vw` part does not grow
  with zoom; past 2.5 times, 500% zoom cannot double the text at some widths, which fails WCAG
  1.4.4.
- Put fluid values in tokens. Components use the token and never repeat the math.
- For more than two or three sizes, derive a scale: `one-fluid-scale-for-type-and-space`.

## One fluid scale for type and space: `one-fluid-scale-for-type-and-space`

Why: six numbers describe every size and the browser derives the steps, replacing a per-breakpoint
size table and a generator someone must rerun.

Baseline: [`pow()`](https://developer.mozilla.org/en-US/docs/Web/CSS/pow#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it when a design has more than two or three font sizes.

```css
:root {
  --narrow: 20;
  --wide: 77.5;
  --size-narrow: 1.125;
  --size-wide: 1.25;
  --ratio-narrow: 1.2;
  --ratio-wide: 1.25;

  --fluid: clamp(0rem, (100vw - var(--narrow) * 1rem) / (var(--wide) - var(--narrow)), 1rem);
  --at-narrow: calc(var(--size-narrow) * (1rem - var(--fluid)));
  --at-wide: calc(var(--size-wide) * var(--fluid));

  --step--1: calc(var(--step-0) / var(--ratio-narrow));
  --step-0: calc(var(--at-narrow) + var(--at-wide));
  --step-1: calc(var(--at-narrow) * var(--ratio-narrow) + var(--at-wide) * var(--ratio-wide));
  --step-2: calc(var(--at-narrow) * pow(var(--ratio-narrow), 2) + var(--at-wide) * pow(var(--ratio-wide), 2));
  --step-3: calc(var(--at-narrow) * pow(var(--ratio-narrow), 3) + var(--at-wide) * pow(var(--ratio-wide), 3));
  --step-4: calc(var(--at-narrow) * pow(var(--ratio-narrow), 4) + var(--at-wide) * pow(var(--ratio-wide), 4));

  --space-s: var(--step-0);
  --space-m: calc(1.5 * var(--step-0));
  --space-l: calc(2 * var(--step-0));
  --space-s-l: calc(var(--at-narrow) + 2 * var(--at-wide));
}

body { font-size: var(--step-0); }
h1 { font-size: var(--step-4); }
h2 { font-size: var(--step-2); }
small { font-size: var(--step--1); }

.card {
  display: grid;
  gap: var(--space-s);
  padding: var(--space-s-l);
}
```

Rules:

- Write the inputs as plain numbers. With `20rem` and `77.5rem` the `--fluid` line divides a length
  by a length, which not every engine supports.
- Change an input in the rule that declares the steps. A step takes its value where it is declared,
  so a ratio set on a descendant changes nothing below it.
- Derive sizes below step 0 from step 0 and the narrow ratio, as `--step--1` does. With both ratios
  a small size can shrink as the screen grows.
- Check the top step against the 2.5 limit in `fluid-sizes-with-clamp`: step `n` passes when
  `(size-wide / size-narrow) × (ratio-wide / ratio-narrow)ⁿ` is 2.5 or less. The example gives
  1.31 at step 4.
- Write a space pair only where a layout uses it, and never for a font size: a pair is steep on
  purpose and breaks that limit.
- For a scale that follows the container, write `100cqi` in place of `100vw`
  (`container-queries-with-container-units`, `layout.md`).
- Components use the tokens and never repeat the math.
