# Design tool terms

How design is made and shared. Each entry gives the term, a definition, and the line between it and
the term most often confused with it.

## Tools: `tools`

### Design system: `design-system`

A shared set of components, tokens, patterns, and guidelines. At its best a living product, not a
static document. The gap between the system and what ships is where inconsistency lives.

**Versus:** visual language is the set of design decisions; a design system packages them as
components, tokens, patterns and guidelines.

### Variables: `variables`

Named containers for values like colors, spacing, or type sizes that can be reused and updated from
one place. Change the variable and everything referencing it updates. The foundation of any scalable
design system.

**Versus:** tokens are variables that carry design decisions both design tools and code read; a
variable is any named value.

### Visual language: `visual-language`

The cohesive set of decisions covering color, type, shape, motion, and tone that makes a product
recognizable across every touchpoint. When it's working, you know the product without seeing its
name.

**Versus:** a design system is the packaged components and tokens; visual language is the set of
decisions they express.

### Prototype: `prototype`

An interactive mockup used to test or communicate a flow before it's built. Can range from a few
linked screens to something nearly indistinguishable from the real product. The fidelity should
match the question being asked.

**Versus:** a mockup is static; a prototype is interactive.

### Redline / annotation: `redline-annotation`

Measurements and notes added to designs to communicate intent to developers: spacing values, color
tokens, interaction behavior, edge cases. Less necessary when teams share a design system, but still
useful for anything non-standard.

**Versus:** handoff is the moment design moves to engineering; redlines are the measurements and
notes that carry it.

### HiDPI / Retina: `hidpi-retina`

Screens with twice or more the pixel density of a standard display. Assets not prepared for it look
blurry. Icons, images, and borders all need to account for 2x and sometimes 3x densities.

**Versus:** pixel hinting fits an icon to a standard pixel grid; HiDPI is a denser grid that needs
2x or 3x assets.

### Source of truth: `source-of-truth`

The single place a team defers to for design decisions. Traditionally a Figma file, but increasingly
the codebase itself as teams work closer to the real experience than a facsimile of it. Wherever it
lives, it only works if everyone uses it.

**Versus:** a design system is the shared set itself; the source of truth is wherever the team
defers to for decisions.

### Tokens: `tokens`

Design decisions stored as named variables that both design tools and code can reference. A token
like `--spacing-4` means the same thing in Figma and in a stylesheet. Tokens are what make a design
system portable across platforms.

**Versus:** variables are any named reusable values; tokens are design decisions both design tools
and code reference. Semantic token in `color.md` is a token named for its purpose.

### Artboard / Frame: `artboard-frame`

A named canvas in a design file representing a screen, view, or component. In Sketch they're
artboards, in Figma they're frames. Frames also define clipping, layout grids, and auto layout
behavior, making them more structural than their name suggests.

**Versus:** a prototype links frames into a flow; an artboard or frame is one canvas.

### Handoff: `handoff`

The moment design moves to engineering. Done well, it means accurate specs, shared tokens, and a
designer who stays available for questions. Done poorly, it means developers making design decisions
on their own.

**Versus:** redlines and annotations are the artifacts; handoff is the moment design moves to
engineering.

### Moodboard: `moodboard`

A collection of visual references to explore or communicate a direction before committing. Used to
align stakeholders on tone and aesthetic. The best ones make an argument. The worst are just
Pinterest boards.

**Versus:** visual language is the decided set; a moodboard explores a direction before deciding.

### Open Graph: `open-graph`

The metadata controlling how a link previews when shared: the image, title, and description. Often
an afterthought, but the first impression of a page for most people who don't visit it directly.

**Versus:** a page title and meta description serve search results and the browser tab; Open Graph
serves link previews when shared.

## Sources

Artboard / frame names the design tool's canvas without stating its features.

- **Pointer**: when frame behavior in the tool matters, fetch https://help.figma.com/hc/en-us/articles/360041539473-Frames-in-Figma-Design live.
- **As of**: 2026-10-28
- **Recheck trigger**: the article changes what a frame defines.
