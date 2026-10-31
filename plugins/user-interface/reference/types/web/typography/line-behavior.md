# Line behavior

How lines get their length, where they break, how they end when space runs out, and which
characters belong in them. The rules these explain are in `../typography.md` "Lines and breaking",
"Copy and characters" and "Finish".

## Measure

The measure is the character count per line, and it has a comfort zone: roughly 45-75 characters
for sustained reading, with the mid-60s as the classic target. Beyond it, the eye struggles to
track back and find the next line's start; far below it, reading turns choppy.

The direct way to state it is `max-width: 65ch`: the `ch` unit equals the width of the font's `0`,
so it counts characters natively. A rem-based cap can land in the same zone; the unit is
unimportant so long as a cap exists, and it should be rechecked whenever the body size or family
changes, since the same width holds a different character count in a different font.

## Wrap modes

CSS now offers per-role control over how lines break:

- `text-wrap: balance`: equalizes line lengths across the block. Made for headings; a two-line
  headline splitting 80/20 looks accidental, balanced it looks set.
- `text-wrap: pretty`: spends a little layout budget to avoid ugly breaks, most visibly the single
  orphaned word on a final line. Right for standfirsts, card blurbs, empty-state copy.

Together (balance on the heading, pretty on the supporting text) they cover the usual
hero-section case. Neither belongs on long-form paragraphs: `balance` applies only up to a line
count each browser sets (the pointer below) and bails beyond it, and a fully evened-out paragraph
trades away width that reading actually uses. `pretty` is the exception for long-form text, as
`../typography.md` "Pick a wrap mode per role" states.

- **Pointer**: MDN, `text-wrap` values, the `balance` line limit,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/text-wrap#values>
- **As of**: 2026-10-29
- **Recheck trigger**: a browser changes its `balance` line limit, or that section changes.

`text-wrap: balance` isn't always right: on a 3-line headline it can leave line 1 awkwardly short.
Sometimes a manual break wins.

Baseline: [`text-wrap`](https://developer.mozilla.org/en-US/docs/Web/CSS/text-wrap#browser_compatibility).
As of 2026-10-29, recheck on a status change.

## Overflow protection

Two failure modes, two pins:

- A long unbroken token (a URL, a hash, a compound German noun) will escape its container unless
  `overflow-wrap: break-word` grants permission to split it.
- A short label that wraps mid-phrase (a badge reading "In<br>progress") looks broken.
  `white-space: nowrap` forbids the wrap; combine with truncation if space is genuinely tight.

For justified or very narrow columns, `hyphens: auto` lets the browser break words at
dictionary-correct points; it needs a correct `lang` attribute to know which dictionary.

## Alignment

Left-aligned (`text-align: start`) is the default for a reason: the ragged right edge gives the eye
a landmark. Justification stretches word spaces until both edges are flush; without hyphenation it
opens rivers of white space, and it belongs, if anywhere, in print-like editorial layouts, not in
interfaces. Centering works for short display text and fails for anything that wraps more than
twice.

**Audit: Suggestion.** Justified text in an interface, or centered text that wraps past two lines.

## Cutting text off

- **One line:** the trio of `white-space: nowrap`, `overflow: hidden` and
  `text-overflow: ellipsis` (Tailwind wraps all three in `truncate`).
- **Several lines:** `line-clamp` with the line count, ellipsis included. Recipe
  `long-text-that-wraps-truncates-or-clamps` in `/user-interface:write-css` writes it in its
  prefixed form until unprefixed `line-clamp` is in the browser target.

- **Pointer**: MDN, `line-clamp`, Description, the legacy prefixed form and what it needs,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/line-clamp#description>
- **As of**: 2026-10-29
- **Recheck trigger**: that section changes what the prefixed form needs, or unprefixed
  `line-clamp` reaches Baseline.

Truncation deletes information from view. That's acceptable only when the reader has another route
to the whole string: a tooltip, a `title` attribute, an expandable row, a detail page. A clipped ID
with no way to read the rest is a data-loss bug.

## Casing

`text-transform` restyles case at render time while the source string stays untouched. So: store
copy the way a human would type it, and let the stylesheet decide whether a nav label renders as
"Settings" or "SETTINGS". The payoff comes at every redesign, when casing changes in one declaration
instead of across every string literal. This also keeps screen readers and translation tooling
working with natural text: `<span>GET STARTED</span>` is shouted by screen readers on some setups,
can't be restyled, and breaks search and copy-paste. Write sentence case in the markup and apply
`text-transform: uppercase` with slight positive tracking.

## The right characters

Keyboards offer approximations; typography wants the real marks:

- Quotes in prose curl: `“ ”` and `‘ ’`, and so do apostrophes (`’`). Straight quotes stay in code,
  where they're syntax.
- A numeric or date span takes an en dash, no spaces: `Mon–Fri`, `1998–2004`. The hyphen is for
  hyphenation.
- An interrupting thought takes the em dash (`&mdash;`), not a pair of hyphens. `/ai-slop:audit`
  flags the em dash in interface copy as a writing tell, so in copy a person reads, prefer a comma,
  a colon or parentheses where one keeps the sentence.
- One ellipsis character `…` replaces three periods; it spaces and wraps as a unit. Never type
  `...` in markup: use the `…` character, or `text-overflow: ellipsis` when truncation should
  respond to container width.
- `×`, not `x`, for dimensions.
- `&nbsp;` welds a value to its unit (`42&nbsp;GB`) or a name to its initial, so no line break can
  divorce them.
- `&shy;` (soft hyphen) marks the permitted break points inside a long word; invisible until the
  break is needed.

Code, identifiers, and anything inside `<code>` stay straight.

Hunt for `...` in JSX text and string literals shown to users ("Loading...", "Saving..."), and
straight `'` in contractions in marketing copy. Don't touch strings that are keys, test IDs, or log
messages.

## Language and direction

- Declare `lang` on the document (and on any inline language switch). Quote style, hyphenation
  dictionaries and speech synthesis all key off it. `<html>` with no `lang` also breaks screen
  reader pronunciation and browser translation prompts.
- Right-to-left content needs `dir="rtl"`, and layout code that survives the flip.
- The survival mechanism is logical properties: every physical direction has a flow-relative twin,
  and the twin is always the better choice.

```css
/* Flow-relative: mirrors itself under dir="rtl" */
.timeline-item {
  padding-inline-start: 12px;
  text-align: start;
}

/* Physical: visually wrong the moment direction flips */
.timeline-item {
  padding-left: 12px;
  text-align: left;
}
```

Apply the same substitution to margins, borders, positioning offsets: anything with a left or right
in its name has an `inline-start`/`inline-end` form that should replace it. Recipe:
`logical-properties` in `/user-interface:write-css`.
