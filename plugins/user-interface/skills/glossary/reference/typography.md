# Typography terms

How text is set, spaced, and read. Each entry gives the term, a definition, and the line between it
and the term most often confused with it.

## Typography: `typography`

### Kerning: `kerning`

The space between two specific characters, adjusted manually. Different from tracking, which affects
all characters equally.

**Versus:** tracking spaces every character in a run evenly; kerning moves one pair.

### Leading: `leading`

The vertical space between lines of text. Too tight and text suffocates. Too loose and it stops
reading as a paragraph.

**Versus:** tracking is horizontal space between letters; gap is space between layout children.

### Tabular nums: `tabular-nums`

A font feature that gives every digit the same width so numbers in columns stay aligned as they
change. Essential for prices, stats, and any data that updates.

**Versus:** Tabular numbers in `motion.md` is the same feature named for counters and timers;
proportional figures are the default, each digit at its own width.

### Weight: `weight`

How thick or thin a typeface's strokes are. Bold is for UI emphasis and hierarchy. Italic is for
linguistic stress or citation, not UI hierarchy.

**Versus:** a heavier weight is a different style of the same family; faux bold is the engine
thickening a font that has no bold.

### Cap height: `cap-height`

The height of a capital letter. Along with x-height, it determines how large a font feels on screen.
Useful when matching fallback fonts or pairing typefaces.

**Versus:** x-height measures lowercase letters; cap height measures capitals.

### Font smoothing: `font-smoothing`

How the browser renders font edges. On Mac, antialiased renders thinner and lighter than the
default. Designers often apply it globally for a crisper feel, though it reduces fidelity on
non-retina screens.

**Versus:** pixel hinting adjusts the shapes to the grid; font smoothing changes how the edges are
rendered.

### Hyphenation: `hyphenation`

Breaking a word across lines with a hyphen. Helps with narrow columns and justified text. Best left
to the browser automatically to avoid breaking at unexpected moments.

**Versus:** text overflow cuts text that does not fit at all; hyphenation breaks a word so the line
fits.

### Widow: `widow`

A single word left alone on the last line of a paragraph. `text-wrap: balance` can fix it
automatically.

**Versus:** an orphan is a single line stranded at the top of a new column or page; a widow is a
single word on the last line.

### Font stack: `font-stack`

The ordered list of fonts the browser tries before giving up. A well-matched fallback font avoids
layout shift when the primary font loads, since mismatched x-heights and weights cause content to
reflow.

**Versus:** a type scale is a set of sizes; a font stack is a fallback order of typefaces.

### Variable font: `variable-font`

A single font file containing a range of weights, widths, or other axes. Lets you animate weight
without layout shift and reduces font file overhead.

**Versus:** a static font family ships one file per weight or width; a variable font holds the whole
range in one.

### Subscript: `subscript`

Lowered characters for formulas or notation. The HTML `sub` element has the same problem as `sup`:
oversized by default and disruptive to line rhythm if left unstyled.

**Versus:** superscript raises characters; subscript lowers them.

### Tracking: `tracking`

Letter-spacing applied uniformly across a word or block of text. Uppercase labels almost always need
more of it.

**Versus:** kerning adjusts one specific pair of characters; tracking applies evenly across the
whole run.

### Optical kerning: `optical-kerning`

Spacing adjusted by eye rather than the font's built-in metrics. Removes awkward gaps between
certain letter pairs that default metrics leave behind.

**Versus:** kerning by the font's built-in pair metrics follows the font file; optical kerning is
set by eye.

### Type scale: `type-scale`

A predetermined set of font sizes that work together, usually based on a ratio. Picking sizes from
the scale keeps hierarchy consistent.

**Versus:** a font stack is a fallback order of typefaces; clamp makes one size fluid between
bounds.

### x-height: `x-height`

The height of a lowercase letter like x, relative to the cap height. A high x-height makes a font
feel larger at the same point size, which is why two fonts at 16px can look very different in size.

**Versus:** cap height measures capitals; x-height measures lowercase letters.

### Ligature: `ligature`

Two characters that merge into a single glyph to avoid awkward collisions. fi and fl are the most
common. Some ligatures are decorative and belong in display use only.

**Versus:** kerning only changes the space between two characters; a ligature replaces them with one
glyph.

### Text overflow: `text-overflow`

What happens when text is longer than its container. Truncation with an ellipsis is the most common
solution. Use the single unicode character, not three periods, and never cut mid-word.

**Versus:** truncation strategy is the copy decision of where to cut; text overflow is the rendering
behavior.

### Clamp: `clamp`

A technique for fluid type sizing that sets a minimum, preferred, and maximum value. The size scales
smoothly between breakpoints without needing separate declarations at each one.

**Versus:** a type scale is the set of sizes; clamp makes one size scale fluidly between its minimum
and maximum.

### Orphan: `orphan`

A single line of a paragraph stranded at the top of a new column or page. The CSS `orphans` property
targets it. Often fixed manually.

**Versus:** a widow is a single word left on the last line of a paragraph; an orphan is a single
line stranded at the top of a new column or page.

### Line length: `line-length`

How wide a column of text runs. Around 65 characters is comfortable. Wider and the eye struggles to
find the next line.

**Versus:** max-width is the container cap that controls it; line length is the measure of the text
itself.

### Superscript: `superscript`

Raised characters for footnotes or exponents. The HTML `sup` element is too large by default and
disrupts line spacing. Proper superscripts are manually sized and shifted.

**Versus:** subscript lowers characters; superscript raises them.

## Sources

Widow and Orphan name a CSS fix without stating its support.

- **Pointer**: when a widow or orphan fix must work in the project's browser targets, fetch https://developer.mozilla.org/en-US/docs/Web/CSS/text-wrap#balance and https://developer.mozilla.org/en-US/docs/Web/CSS/orphans#browser_compatibility live.
- **As of**: 2026-10-28
- **Recheck trigger**: either page changes the property's values or its compatibility table.

Font smoothing names a platform rendering difference without stating where it applies.

- **Pointer**: when font smoothing matters on a target platform, fetch https://developer.mozilla.org/en-US/docs/Web/CSS/font-smooth#browser_compatibility live.
- **As of**: 2026-10-28
- **Recheck trigger**: the page changes the property's status or its compatibility table.
