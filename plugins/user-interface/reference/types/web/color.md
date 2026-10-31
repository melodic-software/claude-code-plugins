# Color

Read this when a web change picks, converts, derives or audits colors: a palette or tonal scale,
a hover or disabled shade, a contrast failure, a gamut question or a focus ring. The project's own
color tokens and theming mechanism win over every rule here; suggest a change to them, never
override them.

An `oklch()` value describes a color by what the eye sees. Lightness is how bright the color
looks, chroma is how vivid it is, and hue is where it sits on the wheel. Unlike HSL's channels,
none of the three misreports perception, so palette math, contrast repair, and dark mode become
arithmetic instead of eyeballing. Default to oklch for anything new.

The CSS that implements these rules is in `/user-interface:write-css`: its `foundations.md`
recipes `oklch-color` and `one-set-of-color-tokens-for-light-and-dark`, and its `interaction.md`
recipe `one-focus-ring-with-focus-visible`. Read the file below that matches the task:

| Read when | File |
|---|---|
| building a tonal ramp, a hue family or a dark-mode remap, or auditing a scale for hue drift | `color/building-scales.md` |
| a contrast number, a failing pair, or text checked in both themes | `color/contrast.md` |
| rewriting hex, rgb() or hsl() literals as oklch | `color/converting-colors.md` |
| high chroma, Display P3, or a browser target without oklch() | `color/gamut-and-p3.md` |
| detect reports Tailwind | `color/tailwind.md` |

The colors of a dark theme, including the lightness order of its surfaces, are here (section 8);
how the theme switches (`color-scheme`, a theme attribute) is the `theming` concern, and the right
theme at first paint is the `layout-stability` concern.
Borders and shadows as depth (which one to use, layered shadows)
are the `shape-and-depth` concern; the color of a 1px border is here (section 8). The principle of
semantic tokens and perceptual color spaces is stated in the `web-layout` concern; the detailed
color rules are here.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

## 1. Before touching any code

**Work inside the project's existing styling system.** Look at how colors are already declared
(plain CSS custom properties, a Tailwind `@theme` block, CSS-in-JS theme objects, generated design
tokens) and write your change in that same mechanism. A color fix is never a reason to bolt on a
parallel theming layer.

**Audit: Important.** A color change that adds a second token or theming mechanism beside the one
the project already uses.

## 2. How to read a value

```css
color: oklch(0.586 0.222 17.585);          /* a saturated crimson */
color: oklch(0.398 0.066 227.392 / 0.9);   /* deep slate-cyan at 90% opacity */
```

The channels, in order:

- **L** runs 0 (black) to 1 (white) and is perceptually even: 0.5 genuinely looks mid-toned
  regardless of hue.
- **C** starts at 0 (pure gray) and tops out around 0.4 in extreme cases; how high it can actually
  go depends on both L and H, because the displayable gamut is lumpy.
- **H** is an angle, 0 to 360°. Rough landmarks: ~20 red, ~90 yellow, ~145 green, ~195 cyan, ~260
  blue, ~330 pink. A pure gray has no hue: write `none` there (`oklch(0.5 0 none)`); the rule and
  its severity are in `color/converting-colors.md`.
- Opacity, when needed, goes after a slash, never as a fourth comma-separated argument.

Three decimals per channel is plenty of precision; trim trailing zeros and write `-0` as plain
`0`.

**Audit: Suggestion.** An oklch channel written with more than three decimals, trailing zeros, or
`-0`.

Which browsers parse `oklch()` is in the Baseline link of the `oklch-color` recipe; check it
against the project's browser targets, and use `color/gamut-and-p3.md` for a target that predates
it.

**Audit: Blocking.** `oklch(0.5, 0.1, 200, 0.5)` comma-style alpha: invalid, so the declaration is
dropped; alpha goes after `/`.

## 3. Operating principles

**Everything new is oklch.** When editing code that already uses hex/`rgb()`/`hsl()`, swap the
values and nothing else: structure, keywords like `currentColor` or `transparent`, and
hex-expecting third-party config all stay put. Details in `color/converting-colors.md`.

**Audit: Suggestion.** A fresh hex or `hsl()` literal landing in new code → express it as oklch.
A fresh `rgb()` literal counts too. A hex counts here only where it defines a color token outside a
Tailwind `@theme` block, which `color/tailwind.md` grades; a raw hex used in place of a token is
graded once, under section 5.

**L answers "light or dark."** A surface with L above 0.6 reads as light and wants dark text on it;
at or below 0.6, reach for light text. No luminance formula needed for the first pass.

**Contrast lives in the L gap.** Chroma and hue barely move contrast; the distance in L between a
foreground and the background it renders on is what counts. To repair a failing pair, move only L.
WCAG 2.2 AA is the bar: 4.5:1 for body text, 3:1 for large text and for UI components and
graphics (success criteria 1.4.3 and 1.4.11). APCA is an advisory second check, not a standard;
the WCAG 3 draft has not chosen its contrast algorithm. Full guidance, and the pointer to these
standards, in `color/contrast.md`.

Low-contrast text "fixed" by pumping saturation → does nothing; widen the L gap instead. The
severity of that finding is in `color/contrast.md`.

**One hue per ramp.** Every step of a tonal scale keeps the identical H. If converting an old scale
to oklch reveals more than about 10° of hue spread between its ends, the ramp drifts visibly:
rebuild it. How, and the severity of a drifting ramp, in `color/building-scales.md`.

**Vividness is relative, not absolute.** Each hue has its own chroma ceiling at a given lightness,
so two hues sharing one absolute C won't look equally saturated. For sibling colors, hold L
constant and give each hue the same *fraction* of its own ceiling.

One C value copied verbatim between hues ("all our 500s use 0.19") → uneven vividness; use per-hue
percentages of the ceiling. The severity is in `color/building-scales.md`.

**Check the gamut before shipping high chroma.** Plenty of syntactically valid oklch values can't
be shown on an sRGB screen. Clamp C (holding L and H) until the color fits, and serve P3-only
chroma behind a `@media (color-gamut: p3)` gate on top of an sRGB base value. Patterns in
`color/gamut-and-p3.md`.

Chroma beyond the sRGB ceiling with no fallback → clips unpredictably; clamp, then layer P3 via
media query. The severity is in `color/gamut-and-p3.md`.

**HSL lies about lightness.** Blue at 50% L and yellow at 50% L are nowhere near equal
perceptually. Use OKLCH when lightness must actually match.

## 4. Numbers worth memorizing

- Light-vs-dark surface cutoff: **L 0.6**
- Against a very light ground (L ≥ 0.85), text needs **L ≤ 0.45**; against a very dark ground
  (L ≤ 0.25), text needs **L ≥ 0.75**: heuristics, confirm with a real check
- Visible hue drift across a ramp: spread **> 10°**
- WCAG 2.2 AA: **4.5:1** body text; **3:1** large text (18pt, or 14pt bold) and UI components and
  graphics. AAA: **7:1** body text, **4.5:1** large text
- Contrast repairs touch **L only**: C and H stay

## 5. Derived and semantic colors

Derive hover states with `color-mix(in oklch, var(--color) 85%, black)`, not a hand-picked darker
hex: hardcoded hexes drift hue unexpectedly. Recipe: `oklch-color`.

**Audit: Suggestion.** A hover, pressed or tint shade hardcoded as a second literal instead of
derived from its base with `color-mix(in oklch, ...)`.

Build light tints by reducing chroma in OKLCH, not by dropping opacity: opacity tints go gray and
lifeless.

**Audit: Suggestion.** A light tint made with opacity over the page instead of a lower-chroma
OKLCH color.

Semantic tokens (`--color-border-subtle`) over raw hex scattered through the codebase. Hardcoded
values break the moment anything changes.

**Audit: Important.** Raw hex values instead of semantic tokens.

Disabled states: use a dedicated muted color token, not `opacity: 0.4`. Opacity-based disabling
passes contrast checks on some backgrounds and fails on others; the token is predictable.

**Audit: Important.** `opacity` on `:disabled` in place of a muted color token.

## 6. Neutrals and status colors

Neutrals should agree with the brand hue: blue UIs want cool grays. Warm grays fight blue.

Never use pure `#808080` gray: it reads as placeholder. Tint neutrals with a slight hue bias and
they read as designed.

**Audit: Suggestion.** Untinted mid-gray neutrals, or neutrals whose hue fights the brand hue.

If green is your primary brand color, don't also use green for success states: users can't
distinguish "primary action" from "it worked". Pick a distinct confirmation color.

**Audit: Important.** A success state in the same hue as the primary action color.

## 7. The focus ring color

The focus ring's color is one token, `--focus-ring`: a theme-aware neutral that keeps 3:1 against
adjacent colors in both themes, or a two-color ring where backgrounds vary. The default example is
the project's highest-contrast gray step (`--gray-12`). The bar is the 3:1 of success criterion
1.4.11, not a hue: a neutral that meets it in both themes holds on most surfaces, and a ring drawn
in two colors at least 9:1 apart keeps one of them at 3:1 whatever sits behind it (WCAG technique
C40). Where the project already has a focus token, use it and check it against this bar.

Form controls resolve their focus color to this token. Drawing the ring (`:focus-visible`, offset,
width, forced-colors) is the `one-focus-ring-with-focus-visible` recipe; whether focus is visible
at all is the `accessibility` concern.

**Audit: Important.** A focus ring color under 3:1 against an adjacent color in either theme, or a
brand-colored ring that disappears on a brand-colored surface.

## 8. Dark mode colors

**Dark mode is a remap, not a repaint.** Flip which end of the scale feeds which role: the token
that was near-white becomes near-black and so on. Because L steps are perceptually even, the
inverted assignments stay balanced without per-color tweaking. Dark mode is not inverted light
mode: preserve the layering hierarchy: the most raised surface stays the lightest (a light dark
gray) and the base surface the darkest.

Follow both as one rule: remap the scale's roles instead of hand-picking a second palette, then
keep surfaces ordered by elevation, each raised surface (card, popover, dialog) a lighter step than
the surface beneath it. Check the remapped surface steps against that order rather than trusting
the inversion. A dark theme assembled from scratch-picked colors → derive it by inverting the light
scale's L assignments. The remap, and the severity of that finding, are in
`color/building-scales.md`.

**Audit: Important.** A dark theme whose raised surfaces are darker than the surface beneath
them.

- **Pointer**: raised surfaces lighter than the base in dark mode, in
  [Apple HIG Dark Mode, iOS and iPadOS](https://developer.apple.com/design/human-interface-guidelines/dark-mode#iOS-iPadOS);
  [Material dialog container color](https://github.com/material-components/material-components-android/blob/66b0eeb53afeb6025ffbbd37734b08e5bce197ed/docs/components/Dialog.md#container-attributes)
  and
  [Material color roles](https://github.com/material-components/material-components-android/blob/66b0eeb53afeb6025ffbbd37734b08e5bce197ed/docs/theming/Color.md#using-the-color-theming-system);
  [shadcn/ui dark card and popover tokens](https://github.com/shadcn-ui/ui/blob/4233ed1caded8c38f4bc14b14afe1f93ebcaf966/apps/v4/app/globals.css#L144-L148)
- **As of**: 2026-10-29
- **Recheck trigger**: any of them changes how a dark theme's raised surfaces relate to the base
  surface.

Light-mode 1px borders: `oklch(0 0 none / 0.08)` recedes naturally; solid `#e0e0e0` looks pasted
on top of the surface.

Dark-mode 1px borders: the opposite: solid (`oklch(0.285 0 none)`-style) sits quietly, while
`oklch(1 0 none / 0.1)` glows.

This applies to layout borders and dividers. The low-opacity white 1px ring that stands in for a
shadow on a raised surface in dark mode (the `shape-and-depth` concern) stays translucent, because
it has to read on whatever lies beneath. Current design systems ship both translucent and opaque
lines, so treat the split as a default, not a hard rule.

- **Pointer**: translucent and opaque 1px lines in dark mode, in
  [shadcn/ui dark `--border`](https://github.com/shadcn-ui/ui/blob/4233ed1caded8c38f4bc14b14afe1f93ebcaf966/apps/v4/app/globals.css#L160);
  [Apple HIG Color, iOS and iPadOS](https://developer.apple.com/design/human-interface-guidelines/color#iOS-iPadOS);
  [Material outlined card stroke](https://github.com/material-components/material-components-android/blob/66b0eeb53afeb6025ffbbd37734b08e5bce197ed/docs/components/Card.md#container-attribute)
- **As of**: 2026-10-29
- **Recheck trigger**: any of them changes its dark-mode line to the other form, or one of them
  names a single default.

**Audit: Suggestion.** A light-mode 1px border drawn in a solid light gray where a translucent
black would recede, or a dark-mode layout border or divider drawn in translucent white where a
solid dark step would sit quietly.

Desaturate brand colors 20–30% for dark mode. Carried over at full saturation they vibrate off
a dark background.

**Audit: Suggestion.** A brand color carried into the dark theme at its light-theme chroma.
