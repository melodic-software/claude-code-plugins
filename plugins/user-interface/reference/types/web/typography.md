# Typography

Read this when text on a web screen is set or reviewed: typefaces and font files, sizes, leading,
tracking, line length, wrapping, truncation, the characters in the copy, and the small details and
floors underneath. The project's own type scale, tokens and typography conventions win over every
rule here; suggest a change to them, never override them.

Nearly everything an interface communicates travels through text, and browsers set text badly by
default in predictable ways: lines run too long, digits jitter as they tick, underlines slice
through descenders, a fake bold sneaks in when a weight file is missing. The remedies are small and
mechanical once you can name them. Context decides which rule applies: a data cell, a hero
headline, a form hint and an essay paragraph each deserve their own treatment, so never flatten
them into a single recipe.

**Stay inside the project's styling idiom.** Before proposing any change, identify how the
codebase expresses styles (Tailwind utilities, vanilla CSS, CSS Modules, styled-components, StyleX)
and phrase every fix in that same idiom. A typography fix is never a justification for bolting a
second styling approach onto a codebase.

The CSS that implements these rules is in `/user-interface:write-css`: its `foundations.md` and
`text-and-media.md` recipes, named by id beside the rule that uses them.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

## Spokes

This file holds the core rules. Each spoke below holds the mechanism, the examples and the code for
one part of them, and some narrower rules with their own **Audit:** lines; read every spoke whose
line matches the work, in a review as in a build. The `typography` row in `reference/concerns.json`
is the source for these conditions.

| Spoke | Read when |
|---|---|
| `typography/typefaces-and-formats.md` | a typeface is chosen, paired or swapped, or font files are added or loaded |
| `typography/font-capabilities.md` | a variable font, font weights, OpenType features, numerals, small caps or superscripts are set |
| `typography/scale-and-rhythm.md` | a type scale, text units, line height, paragraph spacing, letter spacing or text-box trimming is set |
| `typography/line-behavior.md` | line length, wrapping, truncation, text alignment, casing, typographic characters, language or direction is set or reviewed |
| `typography/details-and-floors.md` | underlines, text selection, placeholders, carets, font smoothing, decorative text or minimum text sizes are set or reviewed |
| `typography/tailwind.md` | detect reports Tailwind |

Other concerns own their lines, one home each: input text size on phones is the `touch` concern,
text contrast (body, large text, placeholders, both themes) is the `color` concern, layout that
shifts as fonts load or weights change is the `layout-stability` concern, and spacing between
blocks other than paragraphs is the `web-layout` concern.

## 1. Files and features

**Ship `woff2` and nothing else.** It carries Brotli compression; which browsers accept it is in the
pointer in `typography/typefaces-and-formats.md`. `woff` earns a place only when truly ancient
browsers are a hard requirement; `ttf` and `otf` are uncompressed desktop formats that don't belong
on a web server. Loading strategy (preloading, `font-display`, subsetting) is the project's own
decision; this concern takes no position on it. The loading lines the concern does carry, each
conditioned on the project having no strategy of its own, are in `typography/typefaces-and-formats.md`.

**Audit: Important.** A `ttf` or `otf` file served to the browser, or `woff` with no browser target
that needs it.

**Forbid synthesized styles.** Ask for a bold or italic you never loaded and the browser fabricates
one by thickening or slanting the real glyphs. That's an emergency fallback, not a rendering mode
you want. Declare `font-synthesis: none` so a missing file surfaces as an obvious regression instead
of a quietly ugly imitation. Recipe: `the-reset`.

**Audit: Important.** No `font-synthesis: none`, or a `font-weight` or italic in use that no loaded
font file provides: list each weight used but not loaded. Loading a new font file is the user's
call (it costs bytes); using the nearest loaded weight is the other option.

**Reach for the high-level property before the raw tag.** Write `font-weight: 620`, never
`font-variation-settings: "wght" 620`; `font-optical-sizing: auto`, never a hand-set `"opsz"`;
`font-variant-numeric: tabular-nums`, never `font-feature-settings: "tnum" 1`. High-level properties
still do something sensible when a fallback font renders; the low-level ones silently stop working.
The escape hatches exist solely for what has no property of its own: a custom axis like Fraunces'
`"WONK" 1`, or a numbered stylistic set like `"ss03" 1`.

**Audit: Important.** A registered axis or a feature with its own property set through
`font-variation-settings` or `font-feature-settings`.

**Fixed-width digits on anything that updates.** Most fonts draw a narrow 1 and a wide 4, so a live
timer, price or counter nudges its neighbors on every tick, and a number column (prices, data
tables) doesn't stack and reads as chaos. `font-variant-numeric: tabular-nums` gives all digits one
width and the jitter disappears. Recipe: `tabular-numbers`.

**Audit: Important.** Proportional figures in a number column. A number that updates in place is
graded in the `layout-stability` concern.

## 2. Hierarchy

**Two typefaces cover most products; treat three as the ceiling.** Marketing surfaces can afford
more voice than product UI, but every added face, weight and size dilutes hierarchy instead of
strengthening it. When pairing, chase contrast rather than resemblance: a serif display face over a
sans text face signals intent, while two lookalike sans-serifs just look like a version-control
accident.

**Audit: Suggestion.** More than three typefaces on one surface, or two near-identical faces paired.

**Italic is for citations and linguistic stress; bold is for UI emphasis.** Italic as UI hierarchy
is a publishing convention in the wrong medium.

**Audit: Suggestion.** Italic used to mark hierarchy or emphasis in interface chrome.

**Every size comes from a scale.** Define a small fixed set of sizes and treat departures from it as
exceptions needing justification; scattered one-off values decay fast as a codebase grows. Solo,
generic names such as `text-sm` are workable if the usage rules are written down. On a team, name
steps after roles (`text-caption`, `text-body-lg`) because a role name enforces its own usage in a
way a size name cannot. Recipe: `one-fluid-scale-for-type-and-space`.

**Audit: Important.** A `font-size` that is an arbitrary pixel value off the project's scale.

**Leading follows role.** Display sizes want tight leading, in the neighborhood of `1.1`; body copy
reads best between `1.5` and `1.6`. Always write line-height unitless so it tracks the font size: a
hard-coded `24px` line-height breaks the moment the size changes.

**Audit: Important.** A line-height with a unit on text whose size can change.

**Audit: Suggestion.** Body leading outside `1.5`-`1.6`, or headings left at body leading.

**Tracking follows size.** Big display type usually tightens: a touch of negative letter-spacing.
Tiny uppercase labels open up: a touch of positive spacing keeps the capitals from clumping. Body
text at reading sizes gets neither.

**Audit: Suggestion.** Uppercase labels without loosened tracking, large headings at default
tracking, or tracking set on body text.

## 3. Lines and breaking

**Cap the measure.** The eye loses its return path on long lines. Hold reading columns to roughly
45-75 characters, with about 65 as the sweet spot: `max-width: 65ch` states that directly. A
rem-based cap works too; what matters is that the cap exists and the rendered line count lands in
range.

**Audit: Suggestion.** Body text lines wider than about 75 characters, or a paragraph running the
full width of a wide screen.

**Pick a wrap mode per role.** Headings get `text-wrap: balance`, which evens out the lines.
Standfirsts and card descriptions get `text-wrap: pretty`, which stops a lone word from stranding
on the last line. Long-form body text gets neither: `balance` stops past a line limit the browser
sets (the pointer in `typography/line-behavior.md`), and balancing a full paragraph burns horizontal
space for no reading benefit.

The `the-reset` recipe in `/user-interface:write-css` sets `text-wrap: pretty` on `:root`, and
long-form text inherits it, against this rule. That conflict is open; do not cite the reset as the
recipe for this rule until it is settled.

**Audit: Suggestion.** A heading with no `text-wrap: balance`, or a single orphaned word on a
heading's or a short block's last line.

**Guard against overflow.** Anywhere a URL, token or user-supplied word could punch out of its box,
add `overflow-wrap: break-word`. Anywhere a mid-label break would read as a bug (badges, buttons,
key-value labels) pin it with `white-space: nowrap`. Recipe:
`long-text-that-wraps-truncates-or-clamps`.

Text that overflows its container is graded in the `layout-stability` concern.

**Truncation must leave a path to the full text.** One line: `white-space: nowrap`,
`overflow: hidden`, `text-overflow: ellipsis`. Several lines: `line-clamp`. Either way you're hiding
content, so when the hidden part carries meaning, expose it through a tooltip, a details view, or an
expand affordance. Recipe: `long-text-that-wraps-truncates-or-clamps`, which writes the clamp in its
prefixed form, with every declaration that form needs, until unprefixed `line-clamp` is in the
browser target.

- **Pointer**: MDN, `line-clamp`, Description, the legacy prefixed form and what it needs,
  <https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/line-clamp#description>
- **As of**: 2026-10-29
- **Recheck trigger**: that section changes what the prefixed form needs, or unprefixed
  `line-clamp` reaches Baseline.

**Audit: Important.** Truncated text that carries meaning with no way to read the rest.

## 4. Copy and characters

**Casing is presentation, not data.** Keep strings in natural sentence case and let
`text-transform` shout or capitalize them. Copy typed in caps has to be rewritten at the next
redesign; a transformed string just gets a new class.

**Audit: Suggestion.** All-caps strings in markup or string literals where `text-transform` would
do.

**Type real punctuation.** The characters, and where each one goes, are in
`typography/line-behavior.md` "The right characters".

**Audit: Suggestion.** Three periods for an ellipsis, straight quotes or apostrophes in rendered
prose, a hyphen in a numeric range, or `x` for dimensions, in text a user sees.

## 5. Finish

**Tune the underline.** Browser-default underlines land at an arbitrary position and thickness.
Take both from the font's own metrics via `text-decoration-thickness: from-font` and
`text-underline-position: from-font`, or set thickness, `text-underline-offset` and
`text-decoration-skip-ink` by hand. A dotted line (`text-decoration-style: dotted`) is the
established cue for "hover for more": abbreviations, defined terms. And if the underline animates in
any way beyond a color fade, draw it as its own element; color is the only piece of a native
underline that animates dependably.

**Audit: Suggestion.** Default underlines that cut through descenders, or an animated underline
built on `text-decoration` beyond its color.

**Treat selection as a design surface.** A tinted `::selection` quietly carries the brand into
reading: keep the pairing legible. Put `user-select: none` on control labels, where selection reads
as a glitch, and check that select-all captures only genuine content. Apps chasing a native feel
typically kill selection everywhere except copy-worthy content.

**Audit: Suggestion.** A default selection that clashes with the surface, a `::selection` pair that
is hard to read, or control labels that select on a double click.

**Smooth once, at the root.** Some platforms lay ink on thick; which ones, and what these properties
change there, is in the pointer in `typography/details-and-floors.md`. Set
`-webkit-font-smoothing: antialiased` and `-moz-osx-font-smoothing: grayscale` a single time on the
root layout and let inheritance do the rest. Recipe: `the-reset`.

**Audit: Suggestion.** No smoothing at the root, or smoothing re-declared per component.

**Write direction-neutral CSS.** Use logical properties wherever a physical one exists:
`margin-inline-start` over `margin-left`, `text-align: start` over `left`. Declare `lang` so
hyphenation dictionaries and quote styles resolve correctly, and put `dir="rtl"` on right-to-left
content. Recipe: `logical-properties`.

**Audit: Important.** An `<html>` element with no `lang`, or right-to-left content with no `dir`.

**Audit: Suggestion.** Physical margin, padding or `text-align` where the layout can be mirrored.

## 6. Floors

**Respect the minimums.** Body copy sits at `16px`, the web's default for a reason. Where `16px`
stands against the browser's default size is in the pointer under "Size floors" in
`typography/details-and-floors.md`. Dense UI text
may drop to `14px` (controls, menus), `13px` for captions, and almost never below `12px`. Also
assume readers will zoom, bump the root font size, or override line spacing: nothing should shatter
when they do. Input text on phones is the `touch` concern; the contrast text needs is the `color`
concern.

**Audit: Important.** Body text under `16px`, text under `12px`, or a layout that breaks when the
text is zoomed or the root font size is raised.

## Reviewing typography

1. Detect the styling system first and phrase every fix in it.
2. Sweep the rules against the real text roles on screen (body, headings, labels, live numbers,
   inputs), not just the stylesheet.
3. Report findings grouped by file. Each finding is one bullet: where it is, what's wrong, the
   corrected declaration in the project's idiom, and which rule it serves. Inside a
   `/user-interface:audit` lane, that skill's report shape governs (grouped by severity); each
   finding still carries the corrected declaration and the rule it serves.
4. Stay silent on rules the code already follows; a short list of true issues beats an exhaustive
   tour.
5. Fix with the smallest possible diff. Typography work should not restructure markup unless an
   animated underline or an expandable truncation genuinely requires an extra element.

## Fast diagnoses

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Layout twitches as a number ticks | Proportional figures | `font-variant-numeric: tabular-nums` |
| Bold looks smudged or too black | Weight file never loaded, browser faked it | Load the weight; set `font-synthesis: none` |
| Headline breaks seven words / one word | Default greedy wrapping | `text-wrap: balance` |
| Paragraph ends on a stranded single word | No orphan control | `text-wrap: pretty` |
| Underline slices through g, y, p | Skip-ink or position off | `text-decoration-skip-ink: auto`, `from-font` metrics |
| Long URL blows out a card | No break opportunity | `overflow-wrap: break-word` |
| Weight change does nothing on some machines | Weight set via `"wght"` raw tag | `font-weight` |
| Text feels cramped in one component, airy in another | One-off sizes and line-heights | Route everything through the scale |
| Reading a paragraph feels like work | Measure far beyond 75 characters | Cap the column near `65ch` |
| ALL-CAPS strings scattered through JSX | Casing baked into copy | Sentence case + `text-transform: uppercase` |
| Ellipsis with no way to see the rest | Truncation without an escape hatch | Tooltip, title attribute, or expand control |
| Layout mirrored wrong in Arabic/Hebrew | Physical margin/padding/text-align | Logical properties, `text-align: start` |
| Tapping a field on iPhone zooms the page | Input text under `16px` | The `touch` concern's input size |
| Faint gray text failing audits | Contrast under the bar | Darken until it passes the `color` concern's bar |
