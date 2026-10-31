# Icon terms

How icons are drawn and balanced. Each entry gives the term, a definition, and the line between it
and the term most often confused with it.

## Iconography: `iconography`

### Stroke weight: `stroke-weight`

How thick the lines of an icon are. Thin strokes disappear at small sizes. At large sizes they look
frail. Weight needs to scale with size.

**Versus:** unified weight is the match between icons and the text beside them; stroke weight is the
line thickness itself.

### Filled vs outlined: `filled-vs-outlined`

Two icon styles for communicating state. Filled often signals active or selected. Outlined signals
default. Mixing both without a clear system creates noise.

**Versus:** a contextual swap is switching between the two styles to signal a state change; filled
versus outlined names the two styles.

### Pixel hinting: `pixel-hinting`

Adjusting icon paths to sit cleanly on a pixel grid at small sizes. A full-detail logo at 16px turns
to mush without it.

**Versus:** an icon size system defines which sizes exist; pixel hinting makes each one sit cleanly
on the grid.

### Icon size system: `icon-size-system`

The defined sizes an icon is designed to appear at.

**Versus:** a type scale is the same idea for text; scaling one master icon to every size is what an
icon size system avoids.

### Contextual swap: `contextual-swap`

Switching from an outlined icon to a filled one (or vice versa) to signal a state change like
active, selected, or toggled. The convention needs to be consistent across the product to work.
Mixed usage means users can't learn the pattern.

**Versus:** filled versus outlined names the two styles; a contextual swap is the change between
them.

### Unified weight: `unified-weight`

When icons and surrounding text share the same visual weight. A thin-stroke icon next to bold text
looks like it came from a different product. Icons should feel like they belong to the same visual
family as the type beside them.

**Versus:** stroke weight is the thickness of one icon's lines; unified weight is icons and text
matching each other.

### Optical center: `optical-center`

Where something looks centered versus where it mathematically is. A play button centered by
coordinates looks left-heavy. Nudge it right and it sits.

**Versus:** mathematical or geometric centering uses the bounding box; optical center is where the
shape looks balanced.

### Cap style: `cap-style`

Whether stroke ends are square or round. Round caps feel finished in most UI contexts. Square caps
can read as unrefined.

**Versus:** a line join shapes the corners where strokes meet; cap style shapes the open ends.

### Icon library: `icon-library`

A set of icons drawn at the same size, weight, and radius. Mixing two libraries, even similar ones,
creates subtle mismatches that compound across a product.

**Versus:** an icon size system is the set of sizes; an icon library is the set of drawings sharing
size, weight and radius.

### Meaning collision: `meaning-collision`

When the same icon is used for two different actions in the same product. A star used for both
favoriting and rating. A chevron used for both expanding and navigating. Users learn neither
reliably.

**Versus:** metaphor accuracy asks whether one icon fits its action; meaning collision is one icon
serving two actions.

### Breathing room: `breathing-room`

The space between an icon and its label inside a button or list item. Too close and they look like
they collided. 6 to 8px is a reasonable starting point. The gap is part of the component design, not
an afterthought.

**Versus:** negative space is the empty area of a whole layout; breathing room is the gap between an
icon and its label.

### Metaphor accuracy: `metaphor-accuracy`

Whether the icon actually represents what it's supposed to. A floppy disk for save, a phone handset
for call, a house for home. These work until the generation using them has never seen the physical
object. Worth auditing as your audience ages.

**Versus:** meaning collision is one icon used for two actions; metaphor accuracy is whether the
picture fits the action at all.
