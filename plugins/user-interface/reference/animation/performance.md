# Animation performance

Scope: the web rendering pipeline only. A native or cross-platform stack has its own threads and
render loop; look up its current performance documentation instead of applying this file.

This file answers whether each frame finishes in time, not whether the motion looks right (that
is `catalog.md`). The project's own performance budget and tooling override it. Rendering engines
change what they can accelerate between versions, so this file names the stable rules and points
at the engines' documentation for the rest:

- Pipeline and which properties trigger which step: web.dev, "Rendering performance",
  <https://web.dev/articles/rendering-performance>, and "How to create high-performance CSS
  animations", <https://web.dev/articles/animations-guide>.
- What runs on the compositor beyond transform and opacity: Chrome for Developers, "Hardware
  accelerated animations", <https://developer.chrome.com/blog/hardware-accelerated-animations>,
  and the equivalent notes of each engine the project targets.
- As of 2026-10-11. Recheck when one of these pages changes its property list, or the project's
  browser target adds an engine.

Contents: `frame-budget`, `cost-tiers`, `swap-down-a-tier`, `where-it-runs`, `per-frame-renders`,
`inherited-values`, `blur`, `layer-promotion`, `diagnose`, `report`.

## Frame budget: `frame-budget`

At 60 frames a second each frame has about 16.7 ms (1000 / 60); at 120 it has about 8.3 ms. Design
against the smaller number: high refresh rates are common on phones and laptops. Two things decide
whether a frame fits: how much work the animated property costs, and whether other work on the
main thread can block it.

- Never conclude "it is smooth" from a fast development machine. The bar is a mid-range phone.

## Cost tiers: `cost-tiers`

To show a change, the browser runs up to three steps: layout (size and position of every element),
paint (draw into layers), composite (put the layers on screen). A property enters at one of them:

| Tier | Typical properties | Cost |
|---|---|---|
| Composite only | transform, opacity | cheapest; nothing is re-measured or redrawn |
| Paint and composite | shadows, corner radius, color | a redraw every frame |
| Layout, paint and composite | width, height, padding, margin, offsets, border width | most expensive; one growing element can move everything around it |

Other properties an engine may composite are listed in its own documentation (the pointers above);
treat them as unverified until checked against the project's browser target.

- Layout properties also move the wrong things: animating a sidebar's margin pushes the content
  beside it on every frame; a translate does not.
- A layout animation on a small, isolated element may not drop frames, but an equivalent transform
  animation cannot regress on a slower device. Pick the one with no downside.

## Swap down a tier: `swap-down-a-tier`

| Instead of | Animate |
|---|---|
| width, height or padding to grow or shrink | a scale |
| offsets or margins to move | a translate (percent is relative to the element's own size) |
| a display or visibility swap | opacity |
| an animated box shadow | a drop-shadow filter, or the opacity of a pre-drawn shadow layer |

The shadow is the one people miss: an animated shadow looks harmless but repaints the element on
every frame.

## Where it runs: `where-it-runs`

- Script always runs on the main thread. Motion driven frame by frame from script competes with
  everything else the page is doing; when the main thread is busy, the frame is late.
- Declarative transitions and keyframes, and the platform's script animation API, can run off the
  main thread for compositor-friendly properties. Acceleration is something the browser may grant,
  not a guarantee; which properties are animated is what the code controls.
- Watch for motion that plays while the page is busy: route changes, tab indicators during
  navigation, anything alongside data fetching or hydration. Move it to a declarative animation or
  the platform animation API.
- Animation libraries differ in which path they take, and some take the slower path for their
  convenient shorthand values. Look up the project's library's performance documentation before
  relying on it under load.
- Keep percent-based translates for elements of unknown size even where an engine declines to
  accelerate them: correctness beats a best-effort optimization.

## Per-frame renders: `per-frame-renders`

A hand-rolled animation that updates component state every frame makes a component framework
re-render every frame, and the render alone can exceed the budget. Write the animated value
straight to the element (or through the library's own animated-value mechanism) instead. Look for
state updates inside frame callbacks and pointer, scroll or drag handlers.

## Inherited values: `inherited-values`

An animation that sets a custom property on a parent, read by a transform below it, makes every
descendant recompute style each frame: it uses transform and still drops frames, and gets worse as
content grows. Set the transform on the moving element directly. Suspect this whenever a transform
animation degrades as a list gets longer.

## Blur: `blur`

Animated blur gets expensive fast, and its cost grows with the radius and the blurred area; some
engines are slower than others. A small radius is enough to soften a crossfade. Measure a large or
full-screen blur on the slowest target device before shipping it.

## Layer promotion: `layer-promotion`

A hint that an element will change can promote it to its own layer up front, which avoids a
one-pixel shift when the engine hands the animation over mid-flight.

- Add it last, only after seeing the shift or measuring dropped frames. Browsers already promote
  elements animating transform or opacity, and every promoted layer costs GPU memory.
- Put it on the element that animates, never on every element or on large containers.
- It earns its place on an expensive paint, such as a large filtered element; keep that layer
  small.

## Diagnose: `diagnose`

Name the cause before changing code. Work down this list, ordered by how often each is the cause:

1. Which properties animate? Expand any animate-everything transition and any library shorthand
   into the real properties. Layout properties first, then shadows and radius.
2. Does the drop coincide with a busy page (navigation, fetching, hydration, a long task)?
3. Does a component re-render every frame?
4. Does it get worse as content grows (an inherited value, too many elements animating at once)?
5. Is a custom property animated at all, directly or through a library?
6. Is a large or wide blur animated?
7. Still shifting at start or end? Only now add the layer-promotion hint.

Confirm with a recording, not by feel: the browser's performance panel for dropped frames and long
tasks, its animation panel to slow motion down, and a real mid-range phone over remote debugging.
Desktop CPU throttling models a slow CPU, not a weak GPU or a small memory budget.

## Report: `report`

For each finding, give the element and `path:line`, the cause from the list above, the change, and
whether it was **verified from code** or **needs a device recording**. Order findings by cost:
layout before paint, a busy main thread before an idle one.
