# Engineering terms

How a front end renders, manages state, handles input and ships. Each entry gives the term, a
definition, and the line between it and the term most often confused with it. A term the design
files define is defined once there; its entry here points at that file.

Contents: [Rendering and loading](#rendering-and-loading), [Components and
patterns](#components-and-patterns), [State and data](#state-and-data), [Events and
input](#events-and-input), [CSS behavior](#css-behavior), [Performance](#performance),
[Accessibility mechanics](#accessibility-mechanics), [Delivery and the
network](#delivery-and-the-network).

## Rendering and loading

How a page gets to the screen.

### Server-side rendering (SSR)

The server sends fully-built HTML for each request, so content shows before JavaScript loads.

**Versus:** static site generation builds the HTML once at deploy time; SSR builds it per request.

### Static site generation (SSG)

Pages are pre-built once at deploy time and served as ready-made HTML.

**Versus:** SSR builds HTML per request; SSG builds it once at deploy time.

### Client-side rendering (CSR)

The browser receives a nearly empty page and JavaScript builds the UI.

**Versus:** SSR and SSG send built HTML; CSR sends a nearly empty page and builds it in the browser.

### Hydration

JavaScript attaches behavior to server-rendered HTML so it becomes interactive.

**Versus:** client-side rendering builds the UI from nothing; hydration attaches behavior to HTML
the server already built.

### Hydration mismatch

The server's HTML and the client's first render disagree, causing flicker or console errors.

**Versus:** a layout shift is content moving as it loads; a hydration mismatch is the server and
client disagreeing on the first render.

### Streaming

The server sends HTML in chunks as each part is ready instead of waiting for the whole page.

**Versus:** SSR without streaming waits for the whole page; streaming sends each part as it is
ready.

### Progressive enhancement

The page works without JavaScript; scripts layer the richer experience on top.

**Versus:** graceful degradation starts from the full experience and keeps it usable as features
fail; progressive enhancement starts from a working page and adds to it.

### Flash of unstyled content (FOUC)

Content briefly renders with fallback styles or fonts before the real ones load.

**Versus:** a layout shift is content moving; FOUC is content briefly shown with the wrong styles or
fonts.

### Layout shift

Defined in `layout.md`.

## Components and patterns

Structuring UI code.

### Controlled component

The parent owns an input's value through props and state; every change flows through code.

**Versus:** an uncontrolled component lets the DOM own the value; a controlled one keeps it in
state.

### Uncontrolled component

The DOM owns the input's value; you read it only when you need it.

**Versus:** a controlled component keeps the value in state; an uncontrolled one leaves it to the
DOM.

### Compound components

One component split into pieces that share state, like Tabs, Tabs.List, and Tabs.Panel.

**Versus:** composition over configuration is the principle; compound components are one pattern
that applies it.

### Composition over configuration

Build variations by nesting components instead of piling boolean props onto one.

**Versus:** compound components are one pattern; composition over configuration is the principle of
nesting instead of adding boolean props.

### Headless component

Provides behavior and state with no styling, so you bring your own markup.

**Versus:** a styled component library ships markup and styles; a headless component ships only
behavior and state.

### Render prop

Passing a function for the component to call, letting you decide what it renders.

**Versus:** slot / asChild passes an element to render; a render prop passes a function the
component calls.

### Slot / asChild

A component renders the element you pass instead of its own wrapper, transferring its behavior onto
yours.

**Versus:** a polymorphic component changes its own tag through an `as` prop; slot / asChild renders
the element you pass.

### Portal

Rendering an element outside its parent's DOM tree, like a modal mounted at the body level.

**Versus:** a stacking context limits where z-index competes; a portal moves the element's DOM
position out of its parent.

### Prop drilling

Passing data down through layers of components that don't use it, just to reach a deep child.

**Versus:** lifting state up moves state to a shared parent; prop drilling is the passing down that
can follow.

### Polymorphic component

A component that can render as a different tag or component, usually via an `as` prop.

**Versus:** slot / asChild renders the element you pass; a polymorphic component renders as a tag
you name.

## State and data

Keeping UI and data in sync.

### Optimistic update

Defined in `interaction.md`.

### Single source of truth

One place owns each piece of state; everything else reads from it instead of keeping copies.

**Versus:** derived state is computed from that source; a single source of truth is the one place
that owns it.

### Derived state

A value computed from existing state on the fly instead of stored separately and kept in sync by
hand.

**Versus:** stored state is kept separately and synced by hand; derived state is computed from
existing state on the fly.

### Lifting state up

Moving state to the closest shared parent so sibling components stay in sync.

**Versus:** prop drilling is passing the lifted state down through layers; lifting state up is
moving it to the shared parent.

### Stale-while-revalidate

Show cached data instantly, then fetch a fresh copy in the background and swap it in.

**Versus:** cache invalidation marks data outdated so the next read waits for fresh data;
stale-while-revalidate shows the old data while fetching.

### Cache invalidation

Marking cached data as outdated so the next read fetches fresh data.

**Versus:** stale-while-revalidate keeps showing cached data while refreshing; invalidation marks it
outdated.

### Race condition

Two async operations finish in an unexpected order and the stale result overwrites the fresh one.

**Versus:** a request waterfall is requests run in sequence; a race condition is async results
arriving in the wrong order.

### Request waterfall

Requests that run one after another when they could run in parallel, stacking up their latency.

**Versus:** a race condition is results arriving out of order; a request waterfall is requests that
wait on each other when they need not.

### Polling

Repeatedly asking the server for fresh data on an interval.

**Versus:** a server push sends updates as they happen; polling asks on an interval.

### Idempotent request

Safe to retry: sending it twice has the same effect as sending it once.

**Versus:** exponential backoff is how a retry waits; idempotency is whether retrying is safe.

### Exponential backoff

Retrying a failed request with growing delays between attempts.

**Versus:** polling repeats on a fixed interval while things work; exponential backoff spaces out
retries after failures.

## Events and input

How the browser reports user actions.

### Debounce

Defined in `interaction.md`.

### Throttle

Run the handler at most once per interval while events keep firing, like during scrolling.

**Versus:** debounce waits until the events stop and fires once; throttle fires at a capped rate
while they continue.

### Event bubbling

An event travels up from the element to its ancestors, so parents hear their children's events.

**Versus:** event delegation is the technique that relies on it; bubbling is the event traveling up.

### Event delegation

One listener on a parent handles events from many children instead of a listener on each.

**Versus:** event bubbling is the mechanism; delegation is one parent listener using it.

### Light dismiss

Closing an overlay by clicking outside it or pressing Escape, rather than an explicit close button.

**Versus:** an explicit close button is one way to close; light dismiss closes on an outside click
or Escape.

### Passive listener

A scroll or touch listener that promises not to block scrolling, so the browser keeps it smooth.

**Versus:** throttle limits how often a handler runs; a passive listener promises not to block
scrolling at all.

### Pointer events

One event model that covers mouse, touch, and pen instead of separate handlers for each.

**Versus:** Pointer events in `interaction.md` is the CSS property that turns input on or off for an
element; this is the input event model.

### Hit area

The region that responds to a tap or click, often padded larger than the visible element.

**Versus:** the visible element is what the eye sees; the hit area is what responds. Touch target in
`interaction.md` is the design term.

## CSS behavior

Why styles do what they do.

### Specificity

The scoring system that decides which of two conflicting CSS rules wins.

**Versus:** the cascade is the whole set of rules that resolve competing styles; specificity is one
of them.

### Cascade

The order and priority rules CSS uses to resolve competing styles from different sources.

**Versus:** specificity is one step of it; the cascade is the whole resolution order.

### Stacking context

A group whose children's z-index values only compete with each other, not the rest of the page: why
a huge z-index can still lose to an element outside the group.

**Versus:** z-index is the order value; a stacking context is the group that value competes inside.

### Containing block

The ancestor an absolutely-positioned or percentage-sized element measures itself against.

**Versus:** the parent in the DOM is not always the containing block; the containing block is the
ancestor the element measures against.

### Logical properties

Start/end instead of left/right, so layouts flip automatically for right-to-left languages.

**Versus:** physical properties name left and right; logical properties name start and end.

### Container query

Styles that respond to a component's own size instead of the viewport's.

**Versus:** a breakpoint responds to the viewport; a container query responds to the component's own
size.

### Breakpoint

Defined in `layout.md`.

### Sticky positioning

Defined in `layout.md`.

### Scroll snapping

Scrolling settles onto defined points instead of stopping anywhere, like a carousel.

**Versus:** a carousel is the component; scroll snapping is the scrolling behavior it can use.

### Overscroll behavior

What happens when scrolling hits a boundary: chaining to the parent, rubber-banding, or nothing.

**Versus:** scroll snapping settles inside the content; overscroll behavior decides what happens at
its boundary.

### Safe area

Defined in `layout.md`.

## Performance

Making it fast, keeping it fast.

### Code splitting

Breaking the JavaScript bundle into chunks so each page loads only the code it uses.

**Versus:** lazy loading defers anything until needed; code splitting breaks the bundle into chunks
that can be deferred.

### Lazy loading

Deferring images, components, or code until they're actually needed.

**Versus:** code splitting creates the chunks; lazy loading defers loading them, or images and
components, until needed.

### Tree shaking

Dropping code no one imports from the bundle at build time.

**Versus:** code splitting moves code into separate chunks; tree shaking removes code nothing
imports.

### Preload

Telling the browser to fetch a resource now because it's needed very soon, like a font.

**Versus:** prefetch fetches a likely-next resource in idle time; preload fetches one needed very
soon for this page.

### Prefetch

Fetching a likely-next resource in idle time, like the page behind a link being hovered.

**Versus:** preload is for the current page, now; prefetch is for a likely next page, in idle time.

### Virtualization

Rendering only the visible rows of a long list and recycling them as the user scrolls.

**Versus:** pagination splits a list into pages; virtualization renders only the visible rows of one
long list.

### Memoization

Caching a computed result so it isn't recomputed when the inputs haven't changed.

**Versus:** derived state computes a value from state; memoization caches that result until its
inputs change.

### Re-render

A component's function runs again to reflect new state or props: cheap alone, expensive in storms.

**Versus:** a repaint is the browser drawing pixels again; a re-render is a component function
running again.

### Layout thrashing

Defined in `rendering-performance.md`.

### Long task

JavaScript that hogs the main thread, so clicks, typing, and rendering stall until it finishes.

**Versus:** jank is the visible stutter; a long task is the main-thread work that can cause it.

### Core Web Vitals

Google's user-experience metrics for loading, visual stability and responsiveness.

**Versus:** a lab score measures one test load; Core Web Vitals are field metrics of real users.

## Accessibility mechanics

The machinery behind an accessible UI.

### Semantic HTML

Defined in `accessibility.md`.

### ARIA

Attributes that describe an element's role and state to assistive technology when HTML alone can't.

**Versus:** semantic HTML gets role and state from the element itself; ARIA adds them when HTML
alone cannot.

### Accessible name

The text a screen reader announces for an element, from its label, content, or aria-label.

**Versus:** aria-label is one source of it; the accessible name is what is finally announced.

### Live region

An area whose content changes are announced by screen readers automatically, like a toast.

**Versus:** focus management moves focus; a live region announces a change without moving it.

### Focus management

Deliberately moving keyboard focus: into a dialog when it opens, back to the trigger when it closes.

**Versus:** a focus trap keeps focus inside an overlay; focus management moves it deliberately into
and out of one.

### Focus trap

Defined in `accessibility.md`.

### Roving tabindex

A group is one Tab stop; arrow keys move between the items inside it.

**Versus:** tab order is the sequence of Tab stops; roving tabindex makes a whole group one stop.

### `inert`

Marking a section unfocusable and invisible to assistive tech, like the page behind a modal.

**Versus:** a focus trap keeps focus inside the overlay; inert makes everything behind it
unreachable.

### Reduced motion

Defined in `motion.md`.

## Delivery and the network

Getting assets to the user.

### CDN

Servers distributed near users that serve static files fast.

**Versus:** a cache on the user's device is the browser cache; a CDN caches on servers near the
user.

### Cache busting

Fingerprinting file names with a hash so browsers fetch new versions the moment they change.

**Versus:** cache invalidation marks data outdated in an app cache; cache busting changes a file
name so browsers fetch the new file.

### CORS

The browser's rules for when a page on one domain may call an API on another.

**Versus:** a CDN serves files; CORS rules decide whether a page may call an API on another domain.

### Bundle size

The total JavaScript shipped to the browser: the budget everything above fights over.

**Versus:** a long task is time spent on the main thread; bundle size is how much JavaScript is
shipped.

## Sources

Core Web Vitals is named by what the metrics measure, not by their current names or thresholds.

- **Pointer**: when the current metrics or thresholds matter, fetch https://web.dev/articles/vitals#core-web-vitals live.
- **As of**: 2026-10-28
- **Recheck trigger**: the page adds, drops or renames a Core Web Vital.
