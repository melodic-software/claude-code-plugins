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

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it. A component that re-renders every frame because of a state update in a scroll, drag or frame
handler is graded by the `web-performance` concern; a theme switch that animates every color by the
`theming` concern; looping animation, video and polling that keep running off-screen by the
`web-performance` concern.

Contents: `frame-budget`, `cost-tiers`, `swap-down-a-tier`, `transition-all`, `where-it-runs`,
`per-frame-renders`, `inherited-values`, `blur`, `layer-promotion`, `diagnose`, `report`.

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

Animating `width`, `height`, `margin`, `padding`, `top`, `left`, or `border-width` triggers layout +
paint + composite on every frame. `box-shadow`, `border-radius`, and `color` skip layout but repaint
every frame. `transform` and `opacity` composite only; `filter` and `clip-path` can, depending on
the engine. Whether a given engine and version composites `filter` and `clip-path` is in its own
documentation (the pointers above); treat any property beyond transform and opacity as unverified until checked against the
project's browser target.

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
| `border-radius` | `clip-path: inset(0 round 12px)` |

The shadow is the one people miss: an animated shadow looks harmless but repaints the element on
every frame.

`height: auto` isn't animatable. Measure and animate the pixel value once, animate
`grid-template-rows: 0fr → 1fr`, or clip an inner element. Animating `height` to expand panels
triggers layout every frame; animate `transform: scaleY()` or use a clip, or measure and animate
once. A sidebar that opens forty times a session and animates `width` is a blocker; a rarely opened
settings accordion animating `height` is a should-fix. The measured accordion in `catalog.md`
("Properties") is the sanctioned exception, not a finding.

**Audit: Blocking.** A layout property (`width`, `height`, `margin`, `padding`, `top`, `left`,
`border-width`) animated in `transition:`, `@keyframes` or a library's `animate` on a frequent
interaction, such as a sidebar that animates `width` every time it opens.

**Audit: Important.** The same on an interaction the user rarely triggers, such as a settings
accordion animating `height` outside the measured-height exception.

## No `transition: all`: `transition-all`

**Transition only what changes: never `transition: all`.** With `transition: all` (or Tailwind's
bare `transition` class, which compiles to a broad property list in disguise), every style change
becomes a candidate animation: the browser must track the entire style object, properties you never
meant to tween (padding, shadow, colors) start tweening whenever they change, and the engine loses
the optimizations a narrow, known property list allows. `transition: all 0.3s` is a bug factory: it
silently animates width, height, and color, triggering layout recalculation, and a theme switch
then animates every color at a different timing. List the properties:
`transition: opacity 0.3s, transform 0.3s`.

Illustration (CSS):

```css
/* Do: name each property that actually animates */
.menu-trigger {
  transition-property: translate, opacity;
  transition-duration: 120ms;
  transition-timing-function: ease-out;
}

/* Don't: a shorthand that watches everything */
.menu-trigger {
  transition: all 120ms ease-out;
}
```

Illustration (Tailwind):

```tsx
// Do: the property list is explicit
<a className="transition-[translate,opacity] duration-100 ease-out">

// Don't: bare `transition` is a broad property list in disguise
<a className="transition duration-100 ease-out">
```

Tailwind note: reach for `transition-transform` when only transforms move, after checking in the
pointer below which properties it covers in the project's version. Mixing in non-transform
properties? Use the arbitrary-value form, e.g. `transition-[opacity,filter,scale]`.

- **Pointer**: Tailwind CSS, "transition-property", "Quick reference" (what `transition`,
  `transition-transform` and `transition-all` compile to),
  <https://tailwindcss.com/docs/transition-property#quick-reference>.
- **As of**: 2026-10-29.
- **Recheck trigger**: Tailwind changes the property list of `transition` or `transition-transform`.

**Audit: Important.** `transition: all`, `transition-all`, or Tailwind's bare `transition` class.

## Where it runs: `where-it-runs`

- Script always runs on the main thread. Motion driven frame by frame from script competes with
  everything else the page is doing; when the main thread is busy, the frame is late.
- Declarative transitions and keyframes, and the platform's script animation API, can run off the
  main thread for compositor-friendly properties. Acceleration is something the browser may grant,
  not a guarantee; which properties are animated is what the code controls.
- CSS transitions/animations can run off the main thread for compositor-friendly properties:
  smoother under load. Use for simple,
  predetermined state changes. JS engines (Motion, React Spring) run on `requestAnimationFrame`:
  required for dynamic values, springs, and gesture-driven motion. Pick the simplest tool that
  supports the interaction; don't pay for a JS animation loop to fade a tooltip.
- Anything that animates while the page is busy (route transitions, tab switches during
  navigation, animations that fire alongside data loading or hydration) must not depend on
  `requestAnimationFrame`. Move it to a declarative animation or the platform animation API: for
  predetermined motion during navigation, move it to a CSS transition or animation.
- Animation libraries differ in which path they take, and the path changes between versions. Look
  up the project's library's performance documentation before relying on it under load: whether
  its shorthand values (`x`, `y`, `scale`) run on the main thread or are hardware accelerated like
  a full `transform` string is that page's to say.
- Keep percent-based translates for elements of unknown size even where an engine declines to
  accelerate them: correctness beats a best-effort optimization.

- **Pointer**: Motion, "Performance", "Hardware acceleration", "Independent transforms",
  <https://motion.dev/docs/performance#independent-transforms>.
- **As of**: 2026-10-29.
- **Recheck trigger**: that section changes which values it says are hardware accelerated.

**Audit: Important.** Motion that plays while the page is busy and is driven frame by frame from
script: a navigation element (an active tab indicator, a page transition) animated by a library on
the main thread, or an animation started in the same tick as a fetch or a route change.

## Per-frame renders: `per-frame-renders`

A hand-rolled animation that updates component state every frame makes a component framework
re-render every frame, and the render alone can exceed the budget. State updates per frame are a
re-render storm. Never drive per-frame animation through React state: a re-render per frame drops
frames. Animate outside the render cycle: refs + direct style writes, WAAPI, or a library's
animation loop. The same holds in any component framework, and a library's own animated-value
mechanism counts as its loop. Look for state updates inside frame callbacks and pointer, scroll or
drag handlers.

Illustration (React):

```jsx
// Bad: causes re-render on every frame
const [position, setPosition] = useState(0);

// Good: refs + direct DOM manipulation
const elementRef = useRef(null);
const offset = useRef(0);

useEffect(() => {
  let frame;
  function animate() {
    offset.current += 2;
    elementRef.current.style.transform = `translateX(${offset.current}px)`;
    frame = requestAnimationFrame(animate);
  }
  frame = requestAnimationFrame(animate);
  return () => cancelAnimationFrame(frame);
}, []);
```

## Inherited values: `inherited-values`

An animation that sets a custom property on a parent, read by a transform below it, makes every
descendant recompute style each frame: it uses transform and still drops frames, and gets worse as
content grows. An animated CSS variable on a parent recalculates styles for every descendant on
every frame. A drag that gets slower as the list grows is this. Set the transform on the moving
element directly. Suspect this whenever a transform animation degrades as a list gets longer.

**Audit: Important.** `style.setProperty("--…")` or `style={{ "--x": … }}` updated per frame on a
container whose children read the variable in `transform`.

## Blur: `blur`

Animated blur gets expensive fast, and its cost grows with the radius and the blurred area; some
engines are slower than others. A small radius is enough to soften a crossfade. Measure a large or
full-screen blur on the slowest target device before shipping it.

`filter: blur()` cost explodes past ~20px, in some engines more than others. 2-5px masks a
crossfade; anything larger on an animating or full-screen element is a frame-rate problem. Keep
blurs subtle and off frequently-animating elements. The 20px line is a heuristic, not a measured
limit: no engine documents a radius limit, so the resolved `animation.blur_max_px` holds it as a
default and a project may move it.

**Audit: Important.** `blur(` over `animation.blur_max_px` on an animated element;
`backdrop-filter: blur()` on a full-viewport overlay or on a sticky header over a long scrolling
page; decorative glows on a large blur utility such as `blur-3xl`.

## Layer promotion: `layer-promotion`

A hint that an element will change can promote it to its own layer up front, which avoids a
one-pixel shift when the engine hands the animation over mid-flight.

By default the browser waits until motion actually begins before lifting an element onto a
dedicated compositor layer, and that just-in-time layer creation occasionally eats the opening
frame: a tiny hitch right as movement starts. `will-change` requests the layer up front so the
element is already composited when the animation fires. The hint only matters for properties the
compositor owns; declaring it for layout-bound properties is a no-op.

```css
/* Sensible: the panel slides, so promote its transform ahead of time */
.slide-panel { will-change: transform; }

/* Sensible: a slide paired with a fade */
.slide-panel { will-change: transform, opacity; }

/* Wrong: `all` defeats the point of the hint */
.slide-panel { will-change: all; }

/* Useless: these run through layout and paint regardless */
.slide-panel { will-change: height, color; }
```

| Rendering path | Properties | Does `will-change` pay off? |
| --- | --- | --- |
| Compositor | `opacity`, `transform`; `filter` (blur, brightness) and `clip-path` where the engine composites them | Yes: pre-promotion smooths the first frame |
| Paint | `color`, `background`, `border` | No |
| Layout | `width`, `height`, `top`/`left`, `margin` | No |

- Add it last, only after seeing the shift or measuring dropped frames. Browsers already promote
  elements animating transform or opacity, and every promoted layer costs GPU memory. Browsers have
  gotten good at managing layers themselves, so treat this as a targeted fix: reach for it after
  you've observed a first-frame hiccup (some engines more often than others), never as routine
  seasoning. A page peppered with `will-change` pays real cost for stutters it never had.
- Put it on the element that animates, never on every element or on large containers. Add it only
  to an element that visibly hitches on its first frame, only for compositor properties
  (`transform`, `opacity`, `filter`, `clip-path`), and keep that layer small.
- It earns its place on an expensive paint, such as a large filtered element; keep that layer
  small.

**Audit: Suggestion.** `will-change` on more than a handful of selectors, on `*`, as `will-change:
all`, or naming layout properties (`height`, `color`), where it's a no-op.

## Diagnose: `diagnose`

Name the cause before changing code. Work down this list, ordered by how often each is the cause:

1. Which properties animate? Expand any animate-everything transition and any library shorthand
   into the real properties. Layout properties first, then shadows and radius.
2. Does the drop coincide with a busy page (navigation, fetching, hydration, a long task)?
3. Does a component re-render every frame?
4. Does it get worse as content grows (an inherited value, too many elements animating at once)?
5. Is a custom property animated at all, directly or through a library?
6. Is a large or wide blur animated?
7. Still shifting at start or end? Only now add the layer-promotion hint. Elements can shift ~1px
   at the start/end of transform animations due to the CPU↔GPU rendering handoff.

Confirm with a recording, not by feel: the browser's performance panel for dropped frames and long
tasks, its animation panel to slow declarative motion down, and a real mid-range phone over remote
debugging. Desktop CPU throttling models a slow CPU, not a weak GPU or a small memory budget. Motion
a script drives each frame is captured with a controlled page clock instead: `/playwright:playwright`
animation capture.

- **Pointer**: Chrome DevTools, "Inspect animations", Overview (which animations the panel lists),
  <https://developer.chrome.com/docs/devtools/css/animations#overview>
- **As of**: 2026-10-29
- **Recheck trigger**: the Overview changes which animation kinds the panel supports.

## Report: `report`

For each finding, give the element and `path:line`, the cause from the list above, the change, and
whether it was **verified from code** or **needs a device recording**. Order findings by cost:
layout before paint, a busy main thread before an idle one.
