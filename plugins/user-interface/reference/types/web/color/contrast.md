# Contrast

Read this from `../color.md` when a contrast number is needed, a pair fails, or text must be
checked in both themes. The project's own contrast requirement wins where it is stricter; a
contract, policy or jurisdiction may make one level legally required, so name the requirement the
project is held to.

## First, find the real pair

A contrast number only means something for a specific pairing: the text/icon/control color versus
the surface it actually paints over, usually whatever ancestor supplies the nearest opaque
background. Establish that pairing before measuring anything; checking a foreground against the
wrong surface produces confidently wrong conclusions. Measure the text color against the nearest
opaque ancestor background, not against the page.

## The bar

WCAG 2.2 AA is the bar: 4.5:1 for body text, 3:1 for large text and for UI components and
graphics (success criteria 1.4.3 and 1.4.11). APCA is an advisory second check, not a standard;
the WCAG 3 draft has not chosen its contrast algorithm.

- Body text: at least 4.5:1 for level AA; 7:1 for AAA
- Large text (18pt, or 14pt bold; at 1pt = 1.333px, approximately 24px and 18.5px): 3:1 for
  AA; 4.5:1 for AAA
- UI components and meaningful graphics: 3:1

Text that is pure decoration, part of an inactive control, or part of a logo has no contrast
requirement. Placeholder text isn't exempt: if it carries information it needs 4.5:1 too, which
is one more reason it can't be the label.

Know the ratio's limitation: the formula is blunt, flagging some perfectly readable pairs while
passing some murky ones. Sanity-check with APCA where the two specs disagree: it models
perceived lightness difference, the same foundation oklch is built on. APCA reports Lc, a signed
score: dark-on-light pairs come out positive, light-on-dark negative. Judge the magnitude, ignoring
sign, against the levels APCA publishes for body text, other text and large text. A pair that
passes WCAG and fails APCA is worth fixing; a pair that passes APCA and fails WCAG still fails the
bar.

- **Pointer**: WCAG 2.2 understanding of success criterion 1.4.3, large-scale text and its point
  sizes, <https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html#dfn-large-scale>;
  the WCAG 3 draft's editor's note that its contrast algorithm is yet to be determined,
  <https://www.w3.org/TR/wcag-3.0/#text-contrast-sufficient-minimum>; APCA levels,
  <https://readtech.org/ARC/tests/bronze-simple-mode/>; the sign of Lc by polarity, in the APCA
  reference code, <https://github.com/Myndex/apca-w3/blob/da50930ba8cf8a5ef85d1b269aeba3d83ad91a5a/src/apca-w3.js#L107-L112>
- **As of**: 2026-10-29
- **Recheck trigger**: a WCAG 3 draft adopts a contrast algorithm, WCAG 2.x is superseded as the
  referenced standard, or APCA revises its published levels.

**Audit: Blocking.** Body text under 4.5:1 against its real background, in either theme.

**Audit: Important.** Large text, an icon, a control border or a meaningful graphic under 3:1
against its real background, in either theme; or informative placeholder text under 4.5:1.

## Check every pair in both themes

Contrast was checked in the theme the app was designed in. The muted gray that passes on white
fails on near-black, and the brand color that works as a button fill fails as link text on a dark
surface. Check every pair *twice*, once per theme; how the theme switches is the `theming` concern.

Hunt for:

- the lightest gray text tokens on light backgrounds (`--gray-6`…`--gray-9` used for text,
  `text-gray-400`); placeholder text; text on tinted cards and brand-colored buttons; every one of
  those again in dark mode;
- hardcoded color values inside components (`#6b7280`, `text-gray-500`, `text-black`, `bg-white`)
  that don't flip; muted / secondary / placeholder / disabled text tokens in the dark theme;
- colored badges and alerts (tinted background + same-hue text); text over images;
- `opacity` on `:disabled` (passes on one background, fails on another; use a specific muted
  token: the rule and its severity are in `../color.md`, section 5).

## The one-channel repair

Legacy workflows fix contrast by fiddling with all of R, G, and B (or worse, HSL saturation) until
a checker turns green. In oklch the problem is one-dimensional: perceived contrast tracks the
lightness gap between the pair, while chroma and hue contribute almost nothing. So the repair is
always the same move: push the foreground's L away from the background's L, leaving C and H alone
so the color keeps its identity.

```css
/* fails: lavender text nearly as light as its lavender card */
.card       { background: oklch(0.93 0.03 300); }
.card-label { color: oklch(0.72 0.14 300); }

/* passes: only L moved; the hue and vividness survive */
.card-label { color: oklch(0.42 0.14 300); }
```

Raising C to "make it pop" is the classic dead end: vividness is not contrast.

**Audit: Important.** A contrast repair that changes hue or chroma, or raises chroma, instead of
moving the foreground's L.

## Heuristics for fast triage

Estimating before computing:

- **Is the surface light or dark?** L above 0.6 → treat as light, pair with dark content;
  otherwise pair with light content.
- **Near-white surface (L ≥ 0.85):** foregrounds want L at or under 0.45.
- **Near-black surface (L ≤ 0.25):** foregrounds want L at or over 0.75.

These get you within range in one guess. They don't replace running the actual WCAG calculation
before shipping: borderline cases and mid-tone backgrounds (L between 0.3 and 0.6, where no
foreground has much room) need real numbers.
