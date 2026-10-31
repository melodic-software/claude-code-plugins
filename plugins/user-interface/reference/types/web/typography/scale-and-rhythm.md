# Scale and rhythm

Size, leading and tracking shape text quality more than any decorative flourish. Most text
problems trace back to one of these three. The rules these explain are in
`../typography.md` "Hierarchy"; the project's own scale and tokens win.

## Units for text

- `rem`: relative to the root font size; the default choice for font sizes because it honors the
  reader's browser settings.
- `em`: relative to the current element's font size; handy for things that should ride along with
  the text, like icon sizing or underline offsets.
- `%` on `font-size`: behaves like `em`, relative to the parent.
- `px`: frozen; ignores user font-size preferences. Acceptable for hairlines and borders,
  suspicious on text.

**Audit: Suggestion.** A `font-size` in `px` on body or UI text whose value is on the project's
scale and at or above the size floors. A `px` size off the scale, or under a floor, is one finding
under that rule in `../typography.md` (both **Important**), not a second one here.

## Build a scale, then obey it

A type scale is a short, closed list of sizes that the whole product draws from. Its value is the
constraint: when every size must come from the list, hierarchy stays consistent by construction,
and the alternative (ad-hoc values sprinkled per component) reliably rots as the codebase grows.

A ratio-derived example (minor third, 1.2, on a 16px root; the major third is 1.25, per the ratio
list at <https://typescale.com/>):

```css
:root {
  --step--1: 0.833rem;
  --step-0: 1rem;
  --step-1: 1.2rem;
  --step-2: 1.44rem;
  --step-3: 1.728rem;
  --step-4: 2.074rem;
}
```

Ready-made scales from the project's framework are equally legitimate.

### Name steps by role on teams

`text-lg` describes a size; nothing stops a teammate from using it anywhere. `text-card-title` or
`text-caption` describes a job, and the name polices its own usage. On a solo project, size-based
names plus written conventions are fine; the moment several people commit, role-based names pay for
themselves.

## Leading (line-height)

Two anchors:

- **Body copy:** `1.5`-`1.6`. Reading rhythm needs air between lines.
- **Display and headings:** around `1.1`. Large sizes carry their own optical spacing; default
  leading leaves them gappy.

State it unitless. `line-height: 1.5` recomputes when the font size changes; `line-height: 24px`
stays at 24px and breaks on the first size tweak or user zoom.

## Paragraph spacing

Don't set paragraph spacing to an arbitrary value like 12px; set it to 1x the line-height so the
vertical rhythm stays consistent.

**Audit: Suggestion.** Space between paragraphs set to a value unrelated to their line height.

## Tracking and kerning

These are different mechanisms and only one of them is yours to set routinely:

- **Kerning** is the font's built-in adjustment for specific awkward pairs: the classic gaps in
  "To" or "Wa". Browsers apply it automatically from the font's tables. `font-kerning: none`
  exists, but disabling kerning is a deliberate, unusual act.
- **Tracking** (`letter-spacing`) adds uniform space between all letters, and the right amount
  depends on size and case:
  - Display sizes: slightly negative (large glyphs sit too far apart at their default fit).
  - Small uppercase labels: slightly positive (capitals need daylight to stay distinguishable at
    caption sizes). Default tracking on all-caps looks cramped and amateur.
  - Body text: zero. Reading sizes are fit for reading already.

Display headlines: metric kerning leaves awkward gaps between certain letter pairs; enable optical
kerning for large type where the tool offers it. That is a design-tool setting: CSS has no optical
kerning, and `font-kerning` only applies or drops the font's own pair table (its values are in the
pointer below). So on the web a gappy display pair is a reason to choose a better-kerned display
cut, not a property to set.

- **Pointer**: MDN, `font-kerning` values,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/font-kerning#values>
- **As of**: 2026-10-29
- **Recheck trigger**: CSS Fonts adds a kerning value, or that section changes.

```css
.hero-title {
  font-size: var(--step-4);
  letter-spacing: -0.015em;
}

.eyebrow {
  font-size: var(--step--1);
  text-transform: uppercase;
  letter-spacing: 0.06em;
}
```

Track in `em` so the adjustment scales with the text it belongs to. Larger text wants tighter
letter spacing, smaller text looser: pair each font size with its tracking (a `Text` component is
the right home for this; exact values are font-dependent).

A worked example of asking for it. Bad: "The text in the header feels cramped, can you fix it?"
Good: "Add 0.02em of tracking to the uppercase labels in the header, leave the body text as is."
The good request names the property, the amount, the text it applies to and the text it leaves
alone.

## Cropping built-in space with text-box

Every font reserves headroom above the cap height and legroom below the baseline. That reserve is
why a label never sits dead-center in its button and why a heading's visual top doesn't touch its
container. The `text-box` property crops it, taking an edge selector (`trim-both`, `trim-start`,
`trim-end`) plus where each trimmed edge should land:

- `cap`: the cap height, for a tight top edge
- `alphabetic`: the baseline, for a tight bottom edge
- `text`: the font's own text edges, preserving descender room

```css
/* Center the label optically, not just geometrically */
.tag {
  text-box: trim-both cap alphabetic;
}

/* Pull a section title flush against the block above it */
.section-title {
  text-box: trim-start cap;
}

/* Snug bottom edge only */
.stat-label {
  text-box: trim-end alphabetic;
}
```

Ship it as progressive enhancement: layouts must remain acceptable where the trim never happens.
Recipe: `label-centered-on-its-letters-with-text-box` in `/user-interface:write-css`.

Baseline: [`text-box`](https://developer.mozilla.org/en-US/docs/Web/CSS/text-box#browser_compatibility).
As of 2026-10-29, recheck on a status change.
