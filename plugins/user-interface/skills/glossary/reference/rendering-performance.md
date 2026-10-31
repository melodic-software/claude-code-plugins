# Rendering performance terms

What keeps motion smooth. Each entry gives the term, a definition, and the line between it and the
term most often confused with it.

## Performance: `performance`

### Frame rate (FPS): `frame-rate-fps`

Frames drawn per second; the display's refresh rate sets the budget per frame. 60fps is a common
convention for smooth motion; higher-refresh displays exist.

**Versus:** a dropped frame is one missed deadline; frame rate is how many frames are drawn each
second.

### Dropped frame: `dropped-frame`

A frame the engine didn't draw, causing a tiny hitch in motion.

**Versus:** jank is the visible stutter many dropped frames cause; a dropped frame is one missed
deadline.

### Layout thrashing: `layout-thrashing`

Forcing synchronous layout repeatedly in quick succession, by reading layout from script right after
writing style changes.

Web: reading a geometry property such as `offsetHeight` right after a style write forces the browser
to lay out before the next frame.

**Versus:** animating a layout property re-runs layout every frame; that is a layout-triggering
animation, not thrashing.

### Jank: `jank`

Visible stutter when the engine drops frames because it can't keep up with the animation.

**Versus:** a dropped frame is one missed deadline; jank is the stutter a person sees.

### Compositing: `compositing`

Letting the GPU move or fade an element on its own layer without redoing layout or paint.

**Versus:** GPU compositing in `motion.md` names the properties that stay on this step; compositing
is the step itself.

### Layer promotion hint

Telling the engine ahead of time that an element will animate, so it can give it its own layer.

Web: `will-change`.

**Versus:** compositing is the step the layer runs on; the hint only asks for the layer early, and
every promoted layer costs memory.

## Sources

Layout thrashing takes the strict meaning, repeated forced synchronous layout.

- **Pointer**: when the definition or its fix matters, fetch https://web.dev/articles/avoid-large-complex-layouts-and-layout-thrashing#avoid_layout_thrashing live; correlate with https://developer.chrome.com/docs/performance/insights/forced-reflow.
- **As of**: 2026-10-28
- **Recheck trigger**: the page changes its definition of layout thrashing, or a standards page defines the term.
