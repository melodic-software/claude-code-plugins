# Typography terms

How text is set, spaced, and read. Each entry gives the term, a definition, and the line between it
and the term most often confused with it.

## Typography: `typography`

### Kerning: `kerning`

The space between two specific characters, set by the font's pair metrics, by optical analysis, or
by hand. Different from tracking, which affects all characters equally.

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

How the browser renders font edges. Designers often apply it globally for a crisper feel; whether
it takes effect, and what it costs, depends on the platform.

**Versus:** pixel hinting adjusts the shapes to the grid; font smoothing changes how the edges are
rendered.

### Hyphenation: `hyphenation`

Breaking a word across lines with a hyphen. Helps with narrow columns and justified text. Best left
to the browser automatically to avoid breaking at unexpected moments.

**Versus:** text overflow cuts text that does not fit at all; hyphenation breaks a word so the line
fits.

### Widow: `widow`

The last line of a paragraph stranded alone at the top of a new column or page. The CSS `widows`
property sets how many lines must stay together after the break. Interface writing also uses the
word for a single word alone on a paragraph's last line, which print calls a runt; `text-wrap`
addresses that case.

**Versus:** an orphan is a paragraph's first line stranded at the bottom of a column or page; a
widow is its last line stranded at the top of the next one.

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

Automatic kerning that spaces adjacent characters from their shapes rather than the font's built-in
metrics. Helps where a font has few kern pairs or its metrics leave awkward gaps.

**Versus:** metrics kerning follows the pair values in the font file; manual kerning is set by eye,
one pair at a time; optical kerning is automatic and derived from the glyph shapes.

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

The first line of a paragraph stranded alone at the bottom of a column or page. The CSS `orphans`
property sets how many lines must stay together before the break. Often fixed manually.

**Versus:** a widow is a paragraph's last line stranded at the top of the next column or page; an
orphan is its first line stranded at the bottom of the one before.

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

Widow and Orphan name CSS controls without stating their support.

- **Pointer**: when a widow or orphan fix must work in the project's browser targets, fetch https://developer.mozilla.org/en-US/docs/Web/CSS/text-wrap#values, https://developer.mozilla.org/en-US/docs/Web/CSS/widows#browser_compatibility and https://developer.mozilla.org/en-US/docs/Web/CSS/orphans#browser_compatibility live.
- **As of**: 2026-10-31
- **Recheck trigger**: any of the pages changes the property's values or its compatibility table.

Font smoothing leaves out which platforms honor it and how it renders on each.

- **Pointer**: when font smoothing matters on a target platform, fetch https://developer.mozilla.org/en-US/docs/Web/CSS/font-smooth#browser_compatibility live.
- **As of**: 2026-10-31
- **Recheck trigger**: the page changes the property's status or its compatibility table.
