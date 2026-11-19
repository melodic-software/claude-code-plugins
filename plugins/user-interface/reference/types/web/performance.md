# Web performance

Read this when a web screen loads images, video or heavy code, renders a list that can grow, keeps
work running out of view, fetches content that could be built ahead of time, or sends a request
while the person types. The project's own performance budget, tooling, framework conventions and
dependencies win over every rule here; suggest a change to them, never override them.

Fast UI is mostly about work you *don't* do: don't render DOM nodes nobody can see, don't make the
browser watch properties that never change, don't animate what the GPU can't composite, don't fetch
at request time what you could build at build time, and don't move layout after the user has
started reading it. Most jank is self-inflicted: the fix is usually deleting or deferring work, not
adding cleverness.

A fast development machine hides these costs. Every check here reproduces on a mid-range phone and hides on a
fast laptop.

The examples show the behavior, not code to copy: write each rule in the project's own framework
and its idiom.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

Other concerns own their lines, one home each: an image, video or embed with no dimensions and a
preloaded webfont are the `layout-stability` concern; font files, the weights loaded and subsetting
are the `typography` concern; what an animation costs per frame (which properties animate,
`transition: all`, blur, `will-change`, a custom property on a parent driving its children's
transforms, motion that runs while the page is busy) and reduced motion are the `motion` concern;
a lazy component's sized fallback is the `states` concern; a theme switch that animates every color
is the `theming` concern; the auth-aware call to action that keeps a marketing page static is the
`marketing-pages` concern; choosing a library for a virtualized list is the `component-api`
concern's component-library criteria.

Contents: 1 preload critical, lazy-load the rest, 2 images are the size they're shown at, 3
virtualize long lists, 4 stop work that's off-screen, 5 autoplaying video plays inline, 6 content
routes are static, 7 search and resize handlers are debounced, 8 heavy, rarely-seen UI is split out, 9 nothing
re-renders per frame.

## 1. Preload critical, lazy-load the rest

Preload above-the-fold images:

```html
<link rel="preload" as="image" href="/hero.webp" />
<img src="/gallery-12.webp" loading="lazy" decoding="async" width="600" height="400" alt="…" />
```

Below-the-fold images get `loading="lazy"` so they don't compete with critical resources.

The hero image should be in flight before the CSS finishes parsing. Everything under the fold
should wait. The hero is usually the page's largest contentful paint (LCP) element, the one image
whose arrival the visitor waits for.

Hunt for: the LCP image (hero, first product shot) with no preload; gallery and list images without
`loading="lazy"`; `loading="lazy"` on the hero (delays the one image that matters).

Where the project renders images through a framework's image component, put the LCP hint on the
hero alone and leave the rest to the component's default loading; a hint on every image is the same
as none. Which prop carries the hint depends on the component and its version: use the one its own
documentation names for the version the project runs.

- **Pointer**: MDN, `<img>`, attributes `loading` and `decoding`,
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#loading> and
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#decoding>
- **As of**: 2026-10-29
- **Recheck trigger**: MDN changes what `loading` or `decoding` does.

**Audit: Important.** The above-the-fold hero (the LCP image) with no preload or with
`loading="lazy"`; images below the fold with no lazy loading; or the preload hint on every image.

## 2. Images are the size they're shown at

A 4000px PNG decoded to show a 64px avatar costs bandwidth, decode time, and memory on exactly the
devices that have the least of each.

Hunt for: raw `<img>` in a project that has an image component; `.png` / `.jpg` photos in `public/`
over `performance.image_max_kb`; avatars and thumbnails pointing at the original upload; an image
component with its optimization turned off.

Fix: the framework's image component with `sizes`, or `srcset` by hand; WebP or AVIF for photos;
SVG for anything drawn. A raster image scaled *up* is the mirror-image finding: it ships blurry on
every retina screen.

- **Pointer**: when writing the `sizes` value or the `srcset` list, fetch MDN, `<img>`, attributes
  `srcset` and `sizes`, <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#srcset>
  and <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#sizes>, live.

**Audit: Important.** An image decoded far larger than it is shown (an avatar or thumbnail served
the original upload, a photo over `performance.image_max_kb`, an image component with its
optimization turned off, a raw `<img>` where the project has an image component), or a raster image
scaled up past its own size.

## 3. Virtualize long lists

Don't render hundreds of DOM nodes when only a handful are visible. A virtualized list has three
parts: an outer scroll container with a fixed height and `overflow: auto`; an inner element as tall
as the whole list, so the scrollbar spans every row; and only the visible rows, each placed at its
own offset from the top of the list. When the rows are absolutely positioned, the inner element is
positioned too (`position: relative`), so each row's `top` is measured from the top of the list and
not from the nearest positioned element outside the scroller.

Rendering 2,000 rows renders 2,000 rows. Only what's visible should exist in the DOM. The dev
database had forty rows; the first real customer imports ten thousand. Lists over
`performance.virtualize_min_items` items are virtualized.

Hunt for: `.map()` over data with no cap, no pagination, and no virtualizer, in tables, feeds, logs,
comboboxes, and pickers.

Use the project's existing virtualizer, and its own documentation for how it sizes the inner element
and places the rows. Adding a virtualizer to a table is bigger than a one-line fix: apply it when the
list is simple, otherwise put it on the human list with this section named. Never churn an existing
dependency without being asked.

The human list is the part of your reply or report that names what a person must decide or do
because the change is not yours to make alone. A project with no virtualizer gets one only as a
dependency the person approves.

**Audit: Blocking.** A list, table, feed, log, combobox or picker that renders every item of data
with no upper bound (user content, imports, logs) and has no cap, pagination or virtualizer.

**Audit: Important.** A bounded list of more than `performance.virtualize_min_items` items rendered
whole with no virtualizer.

## 4. Stop work that's off-screen

Pause looping animations, video, and any resource-intensive operation when the element isn't
visible:

```js
const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      startAnimation();
    } else {
      pauseAnimation();
    }
  });
});

observer.observe(element);
```

Looping animations, video, canvases, and polling that keep running while scrolled out of view or in
a background tab burn battery and frame budget for nothing.

Hunt for: `<video autoPlay loop>`, infinite keyframes, `<canvas>` render loops, and `setInterval`
polling with no `IntersectionObserver` or `visibilitychange` anywhere near them.

A background tab is the `visibilitychange` half: pause on `document.hidden` and resume when it
clears. Freezing a time-limited action while the tab is hidden, so the person does not lose it, is
the `accessibility` concern's rule.

**Audit: Suggestion.** A looping animation, video, canvas loop or polling timer that keeps running
out of view or in a background tab, with no `IntersectionObserver` or `visibilitychange` handling.

## 5. Autoplaying video plays inline

An autoplaying video carries both `muted` and `playsinline`, so it starts on its own and plays in
place in the page it was designed for. What each browser does with a video that lacks either is in
the pages the pointer below names.

```html
<video autoplay muted playsinline loop>
  <source src="video.mp4" type="video/mp4" />
</video>
```

Pause it when it scrolls out of view. A looping video below the fold drains a phone battery for
nothing; the IntersectionObserver pattern is in section 4.

Whether a video autoplays at all under reduced motion is the `motion` concern's reduced-motion rule.

- **Pointer**: when checking how a browser treats an autoplaying video, fetch MDN, `<video>`,
  attribute `playsinline`,
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/video#playsinline>, and
  MDN, Autoplay guide, "Autoplay availability",
  <https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Autoplay#autoplay_availability>, live;
  for the iOS side, correlate with WebKit blog, "New `<video>` Policies for iOS", section "WebKit's
  New policies for video", <https://webkit.org/blog/6784/new-video-policies-for-ios/>

**Audit: Important.** An autoplaying `<video>` (`autoplay` or `autoPlay`) missing `muted` or
`playsinline`.

## 6. Content routes are static

Blog posts, docs, changelogs, and pricing don't change per request. Fetching them at request time
adds latency to every visit for content that could be built once and revalidated.

Statically generate all content pages. Blog, changelog, docs, and any frequently updated data:
build time + revalidation, never request-time fetching, through the framework's own mechanism for
building a route ahead and revalidating it on an interval.

Static generation holds for content that is the same for every visitor. A page whose output depends
on who is signed in (an account page, a dashboard, a price or a draft shown only to its owner) stays
rendered at request time, or keeps its shared part static and fetches the per-user part on the
client. A static or cached render must never include one visitor's data, so never remove an auth or
session read to make a route static.

Hunt for: content routes whose data fetch has no caching; a route or layout switched to request-time
rendering by the framework's own setting; a no-store cache option on CMS calls; a cookie or request
header read in a marketing layout (in a framework that renders by route, such a read can opt the
whole subtree out of static rendering; its own documentation says which reads do).

A cookie or header read is a finding only where the route's content is the same for every visitor.
Where it decides what that visitor may see, keep the read: move it out of the shared layout into the
route or component that needs it, never delete it.

An auth-aware CTA (the `marketing-pages` concern) is the usual reason a marketing layout went
dynamic.

**Audit: Important.** A blog, docs, changelog or pricing route whose content is the same for every
visitor, fetched at request time with no caching: a request-time rendering setting, no-store on its
content calls, or a cookie or header read in its layout for no per-visitor decision.

## 7. Search and resize handlers are debounced

A request per keystroke hammers the server and creates race conditions where an older response
overwrites a newer one. Debounce at `performance.search_debounce_ms` and discard stale responses.

Hunt for: `onChange` that calls `fetch` directly; `resize` / `scroll` listeners doing layout reads
(`getBoundingClientRect`, `offsetHeight`) with no throttle; `wheel`, `touchstart` or `touchmove`
listeners not marked `{ passive: true }`.

```js
useEffect(() => {
  const controller = new AbortController();
  const id = setTimeout(() => search(query, controller.signal), 300);
  return () => { clearTimeout(id); controller.abort(); };
}, [query]);
```

Read that last half of the hunt as: a `wheel`, `touchstart` or `touchmove` listener that never
calls `preventDefault()` and is not passive. A `scroll` listener is not this finding. The finding is
a listener that could hold up scrolling and never needs to stop it.

- **Pointer**: when deciding whether a listener needs `passive`, or whether the browser already
  makes it passive, fetch MDN, `EventTarget.addEventListener()`, "Using passive listeners",
  <https://developer.mozilla.org/en-US/docs/Web/API/EventTarget/addEventListener#using_passive_listeners>
  live.

The debounce delays the request, never the input: the field shows every keystroke at once, and any
filtering the page does locally stays immediate. Removing delays from the input path is the `motion`
concern's rule, and the two hold together.

**Audit: Important.** A search or filter input that sends a request on every keystroke, or lets an
older response overwrite a newer one; a `resize` or `scroll` listener that reads layout with no
throttle; or a `wheel`, `touchstart` or `touchmove` listener that never calls `preventDefault()`,
registered as not passive (`{ passive: false }`, or on an element where the browser does not
default it to passive).

## 8. Heavy, rarely-seen UI is split out

Nothing expensive blocks first paint.

A chart library, a rich-text editor, a syntax highlighter, or a confetti effect imported at the top
of the root layout is downloaded and parsed by every visitor, including the ones who never open the
screen that uses it.

Hunt for: large dependencies imported in the root layout or a shared provider; modals and editors
imported statically by the page that *might* open them; whole icon packs or `lodash` imported as a
namespace.

Load such a component on demand, through a dynamic `import()` in the framework's own lazy-loading
form, with a fallback shown while it loads. The fallback reserves the component's box (the `states`
and `layout-stability` concerns). If the project has a bundle analyzer configured, run it and report
the three largest client chunks; if it doesn't, don't add one during a ship check.

**Audit: Important.** A heavy dependency (a chart, an editor, a highlighter, an effect) imported in
the root layout or a shared provider, or statically by a page that opens it only on demand; a whole
icon pack or utility library imported as a namespace.

## 9. Nothing re-renders per frame

A component state update inside a scroll, drag, or `requestAnimationFrame` handler re-renders the
component and its subtree every 16ms. Write to the element instead: set its style (a `transform`)
directly, or set a value the project's animation library applies to the style without a render.

Hunt for: a state setter for a position, progress or scroll offset called inside a scroll,
pointer-move or mouse-move handler or a `requestAnimationFrame` callback; scroll-linked headers and
progress bars.

Why a render per frame misses the frame is the `motion` concern's per-frame renders, and a custom
property on a shared parent driving its children's transforms is its inherited values, with its own
tag; this section holds the one finding for a state update per frame.

**Audit: Blocking.** A state setter called inside a scroll, pointer-move, drag or
`requestAnimationFrame` handler for a value that changes every frame.
