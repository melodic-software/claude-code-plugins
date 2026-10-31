# Details and floors

The last few percent (links, selection, carets, ornament) and the hard floors underneath all of
it. The rules these explain are in `../typography.md` "Finish" and "Floors".

## Underlines

Left alone, the browser invents an underline: its distance and weight are guesses, and the guesses
frequently collide with descenders or come out thread-thin. The cleanest correction defers to the
type designer, whose font carries its own underline metrics:

```css
a {
  text-decoration-thickness: from-font;
  text-underline-position: from-font;
}
```

Manual tuning is the alternative when the font's metrics don't suit the design. Size the parts in
`em` so they scale with the text:

```css
.prose a {
  text-decoration-color: color-mix(in oklab, currentColor 40%, transparent);
  text-decoration-thickness: 0.08em;
  text-underline-offset: 0.16em;
  text-decoration-skip-ink: auto;
  transition: text-decoration-color 150ms ease;
}

.prose a:hover {
  text-decoration-color: currentColor;
}
```

`text-decoration-skip-ink: auto` breaks the line around descending strokes instead of striking
through them.

The style needn't be a solid line. `text-decoration-style` offers dotted, dashed and wavy variants,
and dotted has a settled meaning in interfaces, "there's more here": abbreviations, glossary terms,
anything with a tooltip attached.

```css
abbr[title] {
  text-decoration: underline dotted;
}
```

One hard constraint on animation: of a native underline's parts, only the color transitions
reliably. A link underline that grows, slides or thickens on hover must be its own element (border,
pseudo-element, or background gradient) that you animate freely.

Never underline non-links. Underline is a hyperlink affordance; using it for emphasis trains users
to click text that goes nowhere.

**Audit: Important.** Underlined text that is not a link and has no dotted "more here" meaning.

## Selection and highlights

- `::selection` restyles highlighted text: an easy, quiet brand touch. Whatever
  background/foreground pair you choose has to remain comfortably readable; a decorative selection
  nobody can read is worse than the default.
- `user-select: none` belongs on button labels and control chrome, where a blue smear of selection
  reads as malfunction. Audit what select-all actually grabs on the page: it should collect
  content, not interface.
- Products aiming to feel native (Electron apps, PWAs) usually invert the default: selection off
  globally, re-enabled only on genuinely copyable content.
- `::target-text` styles the passage a text-fragment link (`#:~:text=`) jumps to.
- The CSS Custom Highlight API paints arbitrary ranges (search hits, collaborative cursors) without
  wrapping them in elements.

Baseline: [`::target-text`](https://developer.mozilla.org/en-US/docs/Web/CSS/::target-text#browser_compatibility),
[CSS Custom Highlight API](https://developer.mozilla.org/en-US/docs/Web/API/CSS_Custom_Highlight_API#browser_compatibility).
As of 2026-10-29, recheck on a status change.

## Placeholders and carets

- `::placeholder` restyles the ghost text in empty inputs. Keep it visibly lighter than entered
  text, but not so faint it fails contrast for the people who need it most; the ratio is the
  `color` concern's.
- `caret-color` tints the insertion bar to match the brand. That single property is effectively the
  whole API: replacing the caret outright means rebuilding text editing, which is almost never a
  good trade.

**Audit: Suggestion.** A custom-drawn caret that replaces native text editing.

## Font smoothing

Some platforms render type noticeably heavier than the same font elsewhere; opting into
antialiased/grayscale rendering brings it back toward the intended weight. Which platforms these
two properties act on, and what each value does, is in the pointer below. Declare it once at the
root, both vendor properties together:

- **Pointer**: MDN, `font-smooth` syntax, which covers both vendor properties,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/font-smooth#syntax>
- **As of**: 2026-10-29
- **Recheck trigger**: either vendor property changes the platforms it works on, or a standard
  smoothing property ships.

```css
body {
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
```

Once, globally, at the layout root, not re-declared per component.

## Ornamental text

- `::first-letter`: the classic drop-cap hook, safe to rely on (support: the Baseline line below).
- `initial-letter`: sizes the drop cap in line units; treat as enhancement.
- `::first-line`: styles exactly the first rendered line, reflowing as the container resizes.
- `background-clip: text`: masks a gradient or image to the glyph shapes (pair with transparent
  text color).
- `-webkit-text-stroke`: outlines glyph contours; the prefix is not a reason to avoid it (support:
  the Baseline line below).
- `text-shadow`: a shadow that follows letterforms rather than the box.

Baseline: [`::first-letter`](https://developer.mozilla.org/en-US/docs/Web/CSS/::first-letter#browser_compatibility),
[`initial-letter`](https://developer.mozilla.org/en-US/docs/Web/CSS/initial-letter#browser_compatibility),
[`-webkit-text-stroke`](https://developer.mozilla.org/en-US/docs/Web/CSS/-webkit-text-stroke#browser_compatibility).
As of 2026-10-29, recheck on a status change.

A known artifact: stroked text sometimes shows seams *inside* the letters. Those seams are
overlapping contours in the font itself (variable fonts commonly leave shape intersections
unmerged) and no CSS will remove them; a static instance of the font will.

## The floors

Everything above is negotiable styling; these are not. And remember that readers change text:
zoom, enlarged default font size, forced line spacing. A layout that only works at one size is
already broken.

**Size floors.** Body text belongs at `16px`: a good reading size, not an arbitrary tradition, and
where it stands against the browser's default size is in the pointer below. Secondary UI text may
step down: `14px` for controls and menus, `13px` for captions and metadata, and below `12px` lies
territory that needs an unusually good excuse. Input text on phones keeps its own floor: the `touch`
concern.

- **Pointer**: MDN, `font-size`, the default browser font size under ems,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/font-size#ems>
- **As of**: 2026-10-29
- **Recheck trigger**: that section changes the default size it states.

**Contrast floors.** The ratio each size of text needs is the `color` concern's. Check both
themes if the product has them; gray-on-gray failures love dark mode.
