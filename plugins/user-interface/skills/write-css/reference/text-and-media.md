# Text and media

The project's design system, tokens and conventions override everything in this file. Fill each
`{{key}}` placeholder as [`values.md`](../../../reference/values.md) says. Other numbers in the
examples illustrate the technique.

Each `Baseline:` line links the live compat entry; never copy version numbers from it.

Contents: `long-text-that-wraps-truncates-or-clamps`, `image-box-that-holds-any-upload`,
`tabular-numbers`, `label-centered-on-its-letters-with-text-box`, `icon-sized-by-the-text-beside-it`.

## Long text that wraps, truncates or clamps: `long-text-that-wraps-truncates-or-clamps`

Why: content from users and a CMS is longer than the design; deciding wrap, one-line cut or
few-line clamp up front keeps it from breaking the layout.

Baseline: [`text-overflow`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/text-overflow#browser_compatibility),
[`line-clamp`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/line-clamp#browser_compatibility),
[`overflow-wrap`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/overflow-wrap#browser_compatibility).

Use it on names, titles, URLs and excerpts that come from a user or a CMS.

```css
:root { overflow-wrap: break-word; }

.name {
  white-space: nowrap;
  overflow: clip;
  text-overflow: ellipsis;
}

.excerpt {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  -webkit-line-clamp: 3;
  overflow: clip;
}
```

The rules it serves are the `layout-stability` concern (long values that break the layout) and the
`typography` concern (when truncating is acceptable) of `/user-interface:design`. This recipe is the
CSS for them.

Rules:

- Put the truncation on the element that holds the text. On a flex or grid container the text is
  cut and no ellipsis appears.
- Every flex item between the row and the truncated text must be able to shrink. The reset's
  `min-width: 0` covers that; without it, set `min-inline-size: 0` on each.
- The clamp needs all four declarations. Use the prefixed form until unprefixed `line-clamp` is in
  the target (check its entry below).
- Put padding on a wrapper, never on the clamped element; the next line shows through the bottom
  padding.
- Use `break-word` on the root, not `anywhere`. `anywhere` also shrinks the minimum content width,
  so a box sized by its content collapses to one letter per line.
- A table with automatic layout ignores `break-word`. Set `overflow-wrap: anywhere` on the cell.
- Truncate only text the reader can get in full elsewhere. Never truncate text they must read.
- Where the target does not draw the ellipsis or clamp with `overflow: clip`, use
  `overflow: hidden`.

## Image box that holds any upload: `image-box-that-holds-any-upload`

Why: the box keeps its shape whatever the file's ratio, and has that shape before the file loads,
so nothing shifts.

Baseline: [`aspect-ratio`](https://developer.mozilla.org/en-US/docs/Web/CSS/aspect-ratio#browser_compatibility),
[`object-fit`](https://developer.mozilla.org/en-US/docs/Web/CSS/object-fit#browser_compatibility),
[`outline`](https://developer.mozilla.org/en-US/docs/Web/CSS/outline#browser_compatibility) (following
the radius).

Use it on every image, video or embed whose file you do not control: thumbnails, cover photos,
avatars.

```css
.thumb {
  inline-size: 100%;
  block-size: auto;
  aspect-ratio: {{layout.media_aspect_ratio}};
  object-fit: cover;
  background-color: var(--surface-muted);
}

.avatar {
  flex: none;
  inline-size: {{layout.media_small}};
  block-size: {{layout.media_small}};
  border-radius: 50%;
  object-fit: cover;
  outline: {{css.border_px.standard}}px solid var(--border-subtle);
  outline-offset: -{{css.border_px.standard}}px;
}
```

The rule itself (reserve the space before the file arrives) is the `layout-stability` concern of
`/user-interface:design`; the outline is the `shape-and-depth` concern. This recipe is the CSS for
them.

Rules:

- One axis must be `auto`. A `height` attribute or fixed height wins over the ratio. The reset sets
  `height: auto` on `img`, `svg` and `video`; `block-size: auto` does the same for an `iframe`.
- `object-fit` does nothing until the box has both sizes or a ratio.
- `cover` crops. Use `contain` for logos, product shots and anything that must stay whole. Move the
  crop with `object-position`.
- Leave the background color off an image with transparent areas; it shows through.
- A fixed-size image in a flex row needs both sizes, as the avatar has. With only a width it
  stretches to the row height.
- Where a failed load must not move the layout, put the ratio on a wrapper and give the image
  `inline-size: 100%` and `block-size: 100%`, rather than relying on a broken image's own
  `aspect-ratio`.
- A theme-aware `--border-subtle` built with `light-dark()` needs the `color-scheme` from
  `one-set-of-color-tokens-for-light-and-dark` (`foundations.md`), or the outline stays dark on a
  dark page.

## Tabular numbers: `tabular-numbers`

Why: equal-width digits keep changing numbers from jittering and keep columns aligned.

Baseline: [`font-variant-numeric`](https://developer.mozilla.org/en-US/docs/Web/CSS/font-variant-numeric#browser_compatibility).

Use it on any number that changes or sits in a column: prices, tables, timers, counters.

```css
.price,
td,
time { font-variant-numeric: tabular-nums; }
```

The rules it serves are the `layout-stability` concern (numbers that change in place) and the
`typography` concern (number columns) of `/user-interface:design`. This recipe is the CSS for them.

Rules:

- Do not set it globally. Proportional digits read better in prose.
- The font must ship tabular figures, or nothing changes.

## Label centered on its letters with `text-box`: `label-centered-on-its-letters-with-text-box`

Why: trimming the line box to cap height and baseline makes equal padding look equal in any font.

Baseline: [`text-box`](https://developer.mozilla.org/en-US/docs/Web/CSS/text-box#browser_compatibility).

Use it on single-line labels in buttons, badges and chips.

```css
.button {
  display: inline-block;
  padding-block: {{spacing.control_padding[0]}};
  padding-inline: {{spacing.control_padding[1]}};
  text-box: trim-both cap alphabetic;
}

.button-with-icon {
  display: inline-flex;
  align-items: center;
  gap: {{spacing.xs}};
  padding-block: {{spacing.control_padding[0]}};
  padding-inline: {{spacing.control_padding[1]}};
}

.button-with-icon > span { text-box: trim-both cap alphabetic; }
```

Rules:

- It does nothing on a flex or grid container. An `inline-flex` button that holds an icon needs the
  declaration on the element that wraps the text, as in the last rule.
- The button gets shorter, because padding now starts at the letters: with `0.75rem` padding it
  went from 48px to 35px tall. Raise the padding to keep the height.
- Use it for one line. Descenders hang into the bottom padding, which is the intent.
- Scope it to labels. Never set it on `*`: it shrinks every text block (a one-line 16px/1.5
  paragraph went from 25px to 11px).
- Write no fallback. Without support the label keeps its normal line box.

## Icon sized by the text beside it: `icon-sized-by-the-text-beside-it`

Why: the icon takes its size from the font, so it follows the text and never needs a size per
variant.

Baseline: [`cap` and `lh` units](https://developer.mozilla.org/en-US/docs/Web/CSS/length#browser_compatibility).

Use it on every icon next to a label: buttons, links, list rows, notices.

```css
.with-icon {
  display: inline-flex;
  align-items: baseline;
  gap: {{icon.label_gap_em}}em;
}

.with-icon > svg {
  flex: none;
  block-size: 1cap;
  inline-size: auto;
}

.notice {
  display: flex;
  align-items: start;
  gap: {{icon.label_gap_em}}em;
}

.notice > svg {
  flex: none;
  inline-size: {{icon.size_em}}em;
  block-size: 1lh;
}
```

Rules:

- Never size an icon in `px`. A 16px icon that matches 16px text is 5px to 7px shorter than the
  capitals of 32px text.
- Keep `flex: none`, or a long label squeezes the icon.
- The `svg` needs a `viewBox`; `inline-size: auto` then follows the drawing's ratio.
- Icon sets with padding inside the drawing look small at `1cap`. Raise the number and keep the
  unit, as in `1.2cap`.
- Do not use `align-items: center` on a label that can wrap; the icon then sits beside the middle
  line.
- With `label-centered-on-its-letters-with-text-box` the trimmed label is `1cap` tall, so
  `align-items: center` lines the icon up at both edges.
