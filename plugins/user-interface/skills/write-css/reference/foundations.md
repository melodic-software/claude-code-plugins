# Foundations

The project's design system, tokens and conventions override everything in this file. Fill each
`{{key}}` placeholder as [`values.md`](../../../reference/values.md) says. Other numbers in the
examples illustrate the technique.

Each `Baseline:` line links the live compat entry; never copy version numbers from it.

Contents: `the-reset`, `logical-properties`, `oklch-color`,
`one-set-of-color-tokens-for-light-and-dark`, `fluid-sizes-with-clamp`,
`one-fluid-scale-for-type-and-space`.

## The reset: `the-reset`

Why: one base stylesheet removes the layout, font and touch defaults that every later rule fights.

Baseline: [`text-wrap`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/text-wrap#browser_compatibility),
[`scrollbar-gutter`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scrollbar-gutter#browser_compatibility),
[`interpolate-size`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/interpolate-size#browser_compatibility);
the rest is widely available.

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

button, a, input, select, textarea, [role="button"] { touch-action: manipulation; }

button, [role="button"] {
  user-select: none;
  -webkit-user-select: none;
}
```

In a Tailwind project this goes in the base layer of the global CSS, using the project's tokens.
Merge it into the root rules the project already has; never add a second global stylesheet.

Rules:

- Load every weight and style the design uses. With `font-synthesis: none` a missing bold renders
  as regular.
- With `min-width: 0` on everything, a sized image, icon or avatar in a flex row shrinks for the
  text beside it. Give it `flex: none`.
- The reset removes the tap highlight, so every pressable element needs its own `:active` state:
  `press-feedback` (`interaction.md`).
- Never fix input zoom with `user-scalable=no` or `maximum-scale=1`; that takes zoom from people
  who need it.
- `max(16px, 1rem)` keeps input text at the input floor even when the root font size is set lower.
  If the design needs smaller input text on desktop, set the smaller size outside
  `@media (pointer: coarse)` and keep the floor inside it; the floor and why are the `touch`
  concern's.
- Keep `user-select: none` to controls, never on `body` or links: people copy text. Extend the
  selector to the project's other controls (tabs, chips, drag handles), and give a link or image
  used as a control `-webkit-touch-callout: none` so a long press opens no callout.
- In an app shell with its own scroll areas, add the root rule of
  `no-rubber-band-bounce-on-desktop` (`scroll-and-viewport.md`); a scrolling document leaves it
  out.
- `text-wrap: pretty` on `:root` is deliberate, and long-form body text keeps it; the pointer
  below records what the value is for and what it costs. Where layout speed matters more than the
  last line, as in a long text that re-lays often, such as a live log, set `text-wrap: wrap` on
  that element.
- Typed text inherits `pretty` in `textarea` and `contenteditable`. If lines shift while typing,
  set `text-wrap: stable` on that element.
- The reserved gutter puts centered content slightly off-center on a page too short to scroll.
  Accept it.
- `svh` is for documents and heroes. An app shell with UI pinned to the bottom uses
  `height: 100dvh`, so it tracks the browser toolbar
  (`full-height-that-browser-chrome-cannot-cover`, `scroll-and-viewport.md`).

- **Pointer**: MDN, `text-wrap-style`, "Values" (`pretty`) and "Selecting a value" (its
  performance note),
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/text-wrap-style#values> and
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/text-wrap-style#selecting_a_value>

## Logical properties: `logical-properties`

Why: inline and block sides follow writing direction, so one rule serves left-to-right,
right-to-left and vertical text.

Baseline: [`margin-inline`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/margin-inline#browser_compatibility),
[`inset-inline`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/inset-inline#browser_compatibility).

Use them in place of every left, right, top and bottom: spacing, borders, offsets, alignment.

```css
.card {
  position: relative;
  padding-inline: var(--space-m, {{spacing.m}});
  margin-block-end: var(--space-l, {{spacing.l}});
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

Baseline: [`oklch()`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/color_value/oklch#browser_compatibility),
[`color-mix()`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/color_value/color-mix#browser_compatibility).

Write colors in `oklch()` and derive every related color from a base with
`color-mix(in oklch, …)`. Never hardcode a second hex or `rgba()` for a hover, tint or transparent
version.

```css
:root {
  --primary-hover: color-mix(in oklch, var(--primary), black {{color.hover_mix_percent}}%);
  --primary-subtle: color-mix(in oklch, var(--primary) {{color.subtle_mix_percent}}%, transparent);
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

Baseline: [`light-dark()`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/color_value/light-dark#browser_compatibility);
the image form has its own compat row.

Use it in an app with two designed themes. A single-theme app declares its one scheme instead (the
`theming` concern), and a project with its own theme mechanism keeps it.

```css
/* Two-theme apps only */
:root {
  color-scheme: light dark;
  --background: light-dark(var(--background-light), var(--background-dark));
  --foreground: light-dark(var(--foreground-light), var(--foreground-dark));
}

[data-theme="light"] { color-scheme: light; }
[data-theme="dark"] { color-scheme: dark; }
```

Rules:

- Switch themes by setting `color-scheme`.
- Grays use `none` for the hue so they mix without drifting toward red (`oklch-color`).
- `light-dark()` takes two colors, or two images such as `url()` values or gradients. Check the
  image form's own compat row before relying on it. Anything else that differs by theme needs its
  own rule.
- In a two-theme app, add `<meta name="color-scheme" content="light dark">` so the browser paints
  the right background before the CSS loads. A single-theme app's tag names its one scheme.

- **Pointer**: MDN, `light-dark()`, "Syntax" (the color and image forms),
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/color_value/light-dark#syntax>

## Fluid sizes with `clamp()`: `fluid-sizes-with-clamp`

Why: one declaration that grows with the screen replaces a ladder of breakpoint overrides.

Baseline: [`clamp()`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/clamp#browser_compatibility).

Use it for anything that should grow with the screen, starting with font sizes and section
spacing.

```css
:root {
  --text-body: clamp({{typography.fluid_body.min_rem}}rem, {{typography.fluid_body.preferred_rem}}rem + {{typography.fluid_body.preferred_vw}}vw, {{typography.fluid_body.max_rem}}rem);
  --space-section: {{spacing.section[0]}};
}
```

Rules:

- Write the preferred value as `rem + vw`, never `vw` alone. `clamp(1rem, 1vw, 1.75rem)` stays at
  16px on every screen narrower than 1600px, and a bare `vw` ignores the reader's font size.
- Work the preferred value out from two points. The slope is `(max - min) / (wide - narrow)` in px
  over px; times 100 it is the `vw` number. The `rem` part is `min - slope × narrow`.
- Keep both bounds in `rem` so they follow the reader's font size.
- For a font size, keep the maximum at or below `typography.fluid_max_ratio` times the minimum.
  The key can only lower the WCAG limit of 2.5: the `vw` part does not grow with zoom, so past 2.5
  times, 500% zoom cannot double the text at some widths, which fails WCAG 1.4.4.
- Put fluid values in tokens. Components use the token and never repeat the math.
- For more than two or three sizes, derive a scale: `one-fluid-scale-for-type-and-space`.

## One fluid scale for type and space: `one-fluid-scale-for-type-and-space`

Why: six numbers describe every size and the browser derives the steps, replacing a per-breakpoint
size table and a generator someone must rerun.

Baseline: [`pow()`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/pow#browser_compatibility).

Use it when a design has more than two or three font sizes.

```css
:root {
  --narrow: {{typography.fluid_scale.narrow_rem}};
  --wide: {{typography.fluid_scale.wide_rem}};
  --size-narrow: {{typography.fluid_scale.size_narrow_rem}};
  --size-wide: {{typography.fluid_scale.size_wide_rem}};
  --ratio-narrow: {{typography.fluid_scale.ratio_narrow}};
  --ratio-wide: {{typography.fluid_scale.ratio_wide}};

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
  --space-m: calc({{typography.fluid_scale.space_m_factor}} * var(--step-0));
  --space-l: calc({{typography.fluid_scale.space_l_factor}} * var(--step-0));
  --space-s-l: calc(var(--at-narrow) + {{typography.fluid_scale.space_l_factor}} * var(--at-wide));
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
- Check the top step against the `typography.fluid_max_ratio` limit in `fluid-sizes-with-clamp`,
  never above 2.5: step `n` passes when `(size-wide / size-narrow) × (ratio-wide / ratio-narrow)ⁿ`
  is at or below it. The shipped defaults give 1.31 at step 4.
- Write a space pair only where a layout uses it, and never for a font size: a pair is steep on
  purpose and breaks that limit.
- For a scale that follows the container, write `100cqi` in place of `100vw`
  (`container-queries-with-container-units`, `layout.md`).
- Components use the tokens and never repeat the math.
