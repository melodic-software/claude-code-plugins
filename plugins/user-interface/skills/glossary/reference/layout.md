# Layout terms

How space and structure organize a page. Each entry gives the term, a definition, and the line
between it and the term most often confused with it.

## Layout: `layout`

### Border radius: `border-radius`

The rounding on a corner. An inner element inside a rounded container needs a smaller radius,
calculated as outer radius minus the parent's border width minus the padding, floored at zero; at
zero the inner corner goes square and the two curves no longer share a center. Matching both
creates a visible gap.

**Versus:** nested radius is the outer-minus-border-minus-padding rule for an inner element; border
radius is the rounding itself.

### Negative space: `negative-space`

The empty area around and between elements. It defines shape, creates breathing room, and guides the
eye. Crowding elements together removes clarity, it doesn't add information.

**Versus:** breathing room is the gap between an icon and its label; negative space is the empty
area of the whole layout.

### Auto layout: `auto-layout`

Figma's implementation of flexbox: elements that space themselves, resize with their content, and
respond to direction and alignment rules.

**Versus:** flexbox is the CSS model it imitates; auto layout is the design tool feature.

### Overflow: `overflow`

What happens when content is larger than its container. Hidden clips silently. Scroll adds a
scrollbar. Auto only shows one when needed. Hidden also silently breaks sticky positioning on child
elements.

**Versus:** text overflow is the same question for a line of text; overflow is any content larger
than its box.

### Aspect ratio: `aspect-ratio`

The proportional relationship between width and height. Setting it on images and embeds lets the
browser reserve the right space before the content loads, preventing layout shift.

**Versus:** layout shift is the movement a missing ratio causes; aspect ratio is the proportion that
reserves the space.

### Safe area: `safe-area`

The part of a screen not obscured by notches or home indicators. Fixed bottom elements need to
account for this or they sit underneath the home indicator.

Engineering: the insets that keep content clear of notches, rounded corners, and the home indicator.

**Versus:** viewport units measure the whole window, including the parts a notch or home indicator
covers; the safe area excludes them.

### Breakpoint: `breakpoint`

The point at which a layout changes to suit a different screen size. Best set where the content
actually breaks, not at assumed device widths.

**Versus:** a container query responds to a component's own size; a breakpoint responds to the
viewport.

### Grid: `grid`

A system of columns that organizes layout. 12 columns is conventional. 8 often works better for
simpler layouts.

**Versus:** a baseline grid is horizontal rhythm from line height; a grid is the column system.

### Baseline grid: `baseline-grid`

A horizontal rhythm built from the line-height of body text. Creates consistency in editorial
layouts. Often overkill in product UI.

**Versus:** a column grid organizes horizontal placement; a baseline grid sets vertical rhythm from
line height.

### Gap: `gap`

Space between flex or grid children, set on the parent. Unlike margin, it leaves no trailing space
after the last item.

**Versus:** margin belongs to one child and can leave trailing space; gap is set once on the parent.

### Flexbox: `flexbox`

A CSS layout model for arranging elements in a row or column. Controls direction, alignment,
spacing, and how items grow or shrink to fill available space. The foundation of most modern UI
layout.

**Versus:** CSS grid lays out rows and columns together; flexbox arranges along one axis at a time.

### Layout shift: `layout-shift`

When elements move unexpectedly as a page loads: images popping in, fonts swapping, content
reordering. Avoided by reserving space before content loads and using size-matched font fallbacks.

Engineering: content jumps around as images, fonts, or data load in, moving what the user was about
to click.

**Versus:** layout thrashing is script forcing layout repeatedly; layout shift is visible content
moving as it loads.

### Sticky positioning: `sticky-positioning`

An element that scrolls normally until it hits a threshold, then fixes in place. Requires a parent
that is not set to overflow hidden, which silently breaks it.

Engineering: it pins in place when it reaches an edge of its container.

**Versus:** fixed positioning pins to the viewport at once; sticky scrolls normally until it reaches
its threshold.

### Viewport units: `viewport-units`

Units relative to the browser window. `vw` and `vh` are the classics. `dvh` accounts for the mobile
browser chrome that shows and hides on scroll. Using `vh` for full-screen mobile layouts often
causes overflow because of this.

**Versus:** percentages measure the parent; viewport units measure the window.

### Max-width: `max-width`

A cap on how wide a container gets. Without one, text lines stretch to unreadable lengths on wide
screens.

**Versus:** line length is the measure of the text; max-width is the container cap that limits it.

### Responsive: `responsive`

A design that adapts to different screen sizes rather than being fixed. Achieved through fluid
layouts, flexible images, and breakpoints. The baseline expectation for anything on the web.

**Versus:** adaptive layouts switch between fixed designs per device class; responsive layouts flow
between breakpoints.

### Asymmetry: `asymmetry`

A layout where columns or elements are intentionally unequal. Creates tension and visual interest.
Symmetry is stable but rarely interesting.

**Versus:** symmetry mirrors both sides for stability; asymmetry makes them unequal on purpose.

### Z-index: `z-index`

The stacking order of elements on the same plane. Modals, tooltips, and dropdowns need explicit
z-index values or they clip behind things they should sit above.

**Versus:** a stacking context is the group a z-index competes inside; z-index is the order value
itself.

## Sources

Auto layout is defined by the design tool feature it names.

- **Pointer**: when the tool's auto layout behavior matters, fetch https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout live.
- **As of**: 2026-10-28
- **Recheck trigger**: the article changes how auto layout sizes or spaces children.
