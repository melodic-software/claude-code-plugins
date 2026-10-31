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

The lane where the dev machine lies. Every check here reproduces on a mid-range phone and hides on a
fast laptop.

The examples are React (JSX), Next.js and HTML. In another framework, keep the behavior and write
it in that framework's own idiom.

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

In Next.js, `priority` on the hero `<Image>`, nothing on the rest. Never `priority` on every image;
that's the same as none.

Read `priority` there as a search token for the hero hint, not a fixed prop name: check the
project's Next.js version against the pointer and use the hint its docs name for the LCP image, on
the hero alone, leaving the rest to the framework's default loading. A hint on every image is still
the same as none.

- **Pointer**: MDN, `<img>`, attributes `loading` and `decoding`,
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#loading> and
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#decoding>; Next.js,
  Image Component, `preload`, `priority` and `loading` (from Next.js 16 `priority` is deprecated in
  favor of `preload`, the docs recommend `loading="eager"` or `fetchPriority="high"` over `preload`
  in most cases, and `next/image` loads lazily by default),
  <https://nextjs.org/docs/app/api-reference/components/image#preload>,
  <https://nextjs.org/docs/app/api-reference/components/image#priority> and
  <https://nextjs.org/docs/app/api-reference/components/image#loading>
- **As of**: 2026-10-29
- **Recheck trigger**: MDN changes what `loading` or `decoding` does, or Next.js removes `priority`,
  changes the default `loading`, or changes which hint it recommends for the LCP image.

**Audit: Important.** The above-the-fold hero (the LCP image) with no preload or with
`loading="lazy"`; images below the fold with no lazy loading; or the preload hint on every image.

## 2. Images are the size they're shown at

A 4000px PNG decoded to show a 64px avatar costs bandwidth, decode time, and memory on exactly the
devices that have the least of each.

Hunt for: raw `<img>` in a project that has an image component; `.png` / `.jpg` photos in `public/`
over ~300KB; avatars and thumbnails pointing at the original upload; `unoptimized` on `next/image`.

Fix: the framework's image component with `sizes`, or `srcset` by hand; WebP or AVIF for photos;
SVG for anything drawn. A raster image scaled *up* is the mirror-image finding: it ships blurry on
every retina screen.

- **Pointer**: MDN, `<img>`, attributes `srcset` and `sizes`,
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#srcset> and
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/img#sizes>; Next.js, Image
  Component, `sizes` and `unoptimized`,
  <https://nextjs.org/docs/app/api-reference/components/image#sizes> and
  <https://nextjs.org/docs/app/api-reference/components/image#unoptimized>
- **As of**: 2026-10-29
- **Recheck trigger**: MDN changes how `srcset` and `sizes` select a source, or Next.js changes how
  `sizes` shapes the generated `srcset`.

**Audit: Important.** An image decoded far larger than it is shown (an avatar or thumbnail served
the original upload, a photo over ~300KB, `unoptimized` on `next/image`, a raw `<img>` where the
project has an image component), or a raster image scaled up past its own size.

## 3. Virtualize long lists

Don't render hundreds of DOM nodes when only a handful are visible:

```jsx
import { useVirtualizer } from '@tanstack/react-virtual';

function VirtualList({ items }) {
  const parentRef = useRef(null);

  const virtualizer = useVirtualizer({
    count: items.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 50,
  });

  return (
    <div ref={parentRef} style={{ height: '400px', overflow: 'auto' }}>
      <div style={{ height: virtualizer.getTotalSize(), position: 'relative' }}>
        {virtualizer.getVirtualItems().map((virtualItem) => (
          <div
            key={virtualItem.key}
            style={{
              position: 'absolute',
              top: virtualItem.start,
              height: virtualItem.size,
            }}
          >
            {items[virtualItem.index]}
          </div>
        ))}
      </div>
    </div>
  );
}
```

The inner element carries `position: 'relative'`, as the TanStack Virtual example does, so each row's
`top` is measured from the top of the list and not from the nearest positioned element outside the
scroller.

Rendering 2,000 rows renders 2,000 rows. Only what's visible should exist in the DOM. The dev
database had forty rows; the first real customer imports ten thousand. Lists over ~50 items are
virtualized.

Hunt for: `.map()` over data with no cap, no pagination, and no virtualizer, in tables, feeds, logs,
comboboxes, and pickers.

Use the project's existing virtualizer (`@tanstack/react-virtual`, Virtuoso). Adding a virtualizer
to a table is bigger than a one-line fix: apply it when the list is simple, otherwise put it on the
human list with this section named. Never churn an existing dependency without being asked.

The human list is the part of your reply or report that names what a person must decide or do
because the change is not yours to make alone. A project with no virtualizer gets one only as a
dependency the person approves.

- **Pointer**: TanStack Virtual, Introduction, "The Virtualizer" (the React example's inner element
  is `position: 'relative'` and each item is `position: 'absolute'`),
  <https://tanstack.com/virtual/latest/docs/introduction#the-virtualizer>
- **As of**: 2026-10-29
- **Recheck trigger**: TanStack Virtual renames `useVirtualizer`, `getVirtualItems` or
  `getTotalSize`, or changes how its example positions the items.

**Audit: Blocking.** A list, table, feed, log, combobox or picker that renders every item of data
with no upper bound (user content, imports, logs) and has no cap, pagination or virtualizer.

**Audit: Important.** A bounded list of more than ~50 items rendered whole with no virtualizer.

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

Without `muted`, iOS refuses to autoplay. Without `playsinline`, it hijacks the screen with the
fullscreen player the moment the video starts.

```html
<video autoplay muted playsinline loop>
  <source src="video.mp4" type="video/mp4" />
</video>
```

Pause it when it scrolls out of view. A looping video below the fold drains a phone battery for
nothing; the IntersectionObserver pattern is in section 4.

Whether a video autoplays at all under reduced motion is the `motion` concern's reduced-motion rule.

- **Pointer**: MDN, `<video>`, attribute `playsinline`,
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/video#playsinline>; MDN,
  Autoplay guide, "Autoplay availability",
  <https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Autoplay#autoplay_availability>;
  WebKit blog, "New `<video>` Policies for iOS", section "WebKit's New policies for video", for the
  iOS side, <https://webkit.org/blog/6784/new-video-policies-for-ios/>
- **As of**: 2026-10-29
- **Recheck trigger**: MDN's autoplay guide changes which media may autoplay or what `playsinline`
  does, or WebKit changes when iOS lets a video autoplay or play inline.

**Audit: Important.** An autoplaying `<video>` (`autoplay` or `autoPlay`) missing `muted` or
`playsinline`.

## 6. Content routes are static

Blog posts, docs, changelogs, and pricing don't change per request. Fetching them at request time
adds latency to every visit for content that could be built once and revalidated.

Statically generate all content pages. Blog, changelog, docs, and any frequently updated data:
build time + revalidation, never request-time fetching:

```jsx
// Next.js example
export async function generateStaticParams() {
  const posts = await getPosts();
  return posts.map((post) => ({ slug: post.slug }));
}

export const revalidate = 3600; // Revalidate every hour
```

That is the Next.js App Router. The Pages Router does the same with `getStaticProps`:

```jsx
// Next.js example
export async function getStaticProps() {
  const posts = await fetchPosts();
  return {
    props: { posts },
    revalidate: 3600, // Revalidate hourly
  };
}
```

Static generation holds for content that is the same for every visitor. A page whose output depends
on who is signed in (an account page, a dashboard, a price or a draft shown only to its owner) stays
rendered at request time, or keeps its shared part static and fetches the per-user part on the
client. A static or cached render must never include one visitor's data, so never remove an auth or
session read to make a route static.

Hunt for: `fetch()` in server components / loaders for content routes with no caching; `dynamic =
"force-dynamic"`; `cache: "no-store"` on CMS calls; `cookies()` or `headers()` read in a marketing
layout (it opts the whole subtree out of static rendering).

A `cookies()` or `headers()` read is a finding only where the route's content is the same for every
visitor. Where it decides what that visitor may see, keep the read: move it out of the shared layout
into the route or component that needs it, never delete it.

An auth-aware CTA (the `marketing-pages` concern) is the usual reason a marketing layout went
dynamic.

Where the framework's current caching model replaces these exports, keep the route built ahead
through that model's own mechanism, and apply the same hunt to whatever reads the request; the
pointer says which.

- **Pointer**: Next.js, Caching and Revalidating (Previous Model), "Route segment config
  `revalidate`" and "`dynamic`",
  <https://nextjs.org/docs/app/guides/caching-without-cache-components#route-segment-config-revalidate>
  and <https://nextjs.org/docs/app/guides/caching-without-cache-components#dynamic>; Next.js,
  Route Segment Config, "Version History" (from Next.js 16, `dynamic` and `revalidate` are removed
  when Cache Components is enabled),
  <https://nextjs.org/docs/app/api-reference/file-conventions/route-segment-config#version-history>;
  Next.js, `cookies`, "Good to know" (reading it in a layout or page opts the route into dynamic
  rendering), <https://nextjs.org/docs/app/api-reference/functions/cookies#good-to-know>; Next.js
  Pages Router, `getStaticProps`, "When does getStaticProps run",
  <https://nextjs.org/docs/pages/building-your-application/data-fetching/get-static-props#when-does-getstaticprops-run>
- **As of**: 2026-10-29
- **Recheck trigger**: Next.js changes which exports or functions opt a route into request-time
  rendering, or what replaces `revalidate` under Cache Components.

**Audit: Important.** A blog, docs, changelog or pricing route whose content is the same for every
visitor, fetched at request time with no caching: `force-dynamic`, `no-store` on its content calls,
or `cookies()` or `headers()` read in its layout for no per-visitor decision.

## 7. Search and resize handlers are debounced

A request per keystroke hammers the server and creates race conditions where an older response
overwrites a newer one. Debounce at ~300ms and discard stale responses.

Hunt for: `onChange` that calls `fetch` directly; `resize` / `scroll` listeners doing layout reads
(`getBoundingClientRect`, `offsetHeight`) with no throttle; scroll listeners not marked `{ passive:
true }`.

```js
useEffect(() => {
  const controller = new AbortController();
  const id = setTimeout(() => search(query, controller.signal), 300);
  return () => { clearTimeout(id); controller.abort(); };
}, [query]);
```

`passive` matters for the listeners that can cancel scrolling, `wheel`, `touchstart` and
`touchmove`, not for the `scroll` event itself, which cannot be canceled; the pointer says which of
them a browser already treats as passive. Read the scroll-listener half of the hunt as: a `wheel`,
`touchstart` or `touchmove` listener that never calls `preventDefault()` and is not passive.

- **Pointer**: MDN, `EventTarget.addEventListener()`, "Using passive listeners" (which listeners
  `passive` matters for, and which ones a browser already treats as passive),
  <https://developer.mozilla.org/en-US/docs/Web/API/EventTarget/addEventListener#using_passive_listeners>
- **As of**: 2026-10-29
- **Recheck trigger**: MDN changes which events or targets default to passive, or says `passive`
  matters for the `scroll` event.

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

```jsx
const Editor = dynamic(() => import("./editor"), { loading: () => <EditorSkeleton /> });
```

The `loading` fallback reserves the editor's box (the `states` and `layout-stability` concerns). If
the project has a bundle analyzer configured, run it and report the three largest client chunks; if
it doesn't, don't add one during a ship check.

`dynamic()` is the Next.js form; React's own is `lazy()` under a `<Suspense>` boundary.

- **Pointer**: Next.js, Lazy Loading guide, "Adding a custom loading component" (the `loading`
  option of `next/dynamic`),
  <https://nextjs.org/docs/app/guides/lazy-loading#adding-a-custom-loading-component>; React,
  `lazy`, "Lazy-loading components with Suspense",
  <https://react.dev/reference/react/lazy#suspense-for-code-splitting>
- **As of**: 2026-10-29
- **Recheck trigger**: Next.js renames `next/dynamic` or its `loading` option, or React changes
  where a `lazy` component's fallback comes from.

**Audit: Important.** A heavy dependency (a chart, an editor, a highlighter, an effect) imported in
the root layout or a shared provider, or statically by a page that opens it only on demand; a whole
icon pack or utility library imported as a namespace.

## 9. Nothing re-renders per frame

`setState` inside a scroll, drag, or `requestAnimationFrame` handler re-renders the component and
its subtree every 16ms. Write to the element instead.

Hunt for: `setX` / `setPosition` / `setProgress` / `setScrollY` inside `onScroll`, `onPointerMove`,
`onMouseMove`, `requestAnimationFrame`; scroll-linked headers and progress bars.

```jsx
// Drops frames
setY(nextY);

// Smooth
ref.current.style.transform = `translateY(${nextY}px)`;
// or a Motion value: y.set(nextY)
```

Why a render per frame misses the frame is the `motion` concern's per-frame renders, and a custom
property on a shared parent driving its children's transforms is its inherited values, with its own
tag; this section holds the one finding for a state update per frame.

- **Pointer**: Motion, `useMotionValue`, "API", `set()` (motion values update styles without
  re-rendering React), <https://motion.dev/docs/react-motion-value#set>
- **As of**: 2026-10-29
- **Recheck trigger**: Motion renames motion values or `set()`, or they start re-rendering React.

**Audit: Blocking.** A state setter called inside a scroll, pointer-move, drag or
`requestAnimationFrame` handler for a value that changes every frame.
