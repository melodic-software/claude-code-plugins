# Layout stability

Read this when a web screen loads data, images, fonts or late UI, shows numbers that change, swaps a
label, changes state on hover or selection, restores saved state, or renders text a user or a CMS
wrote: anything that can move the page after the reader has started reading it. The project's own
components, tokens and conventions win over every rule here; suggest a change to them, never
override them.

The CSS that implements these rules is in `/user-interface:write-css`: its `text-and-media.md`
recipes, named by id beside the rule that uses them.

A rule that ends in **Audit:** gives the severity `/user-interface:audit` uses for a finding against
it, and what that finding looks like.

Other concerns own their lines, one home each: which loading, empty or error state a view shows is
the `states` concern, and so is sizing an empty state like the filled one; matching a fallback
font's x-height and weight is the `typography` concern, and so are proportional figures in a static
number column and the variable weight axis; switching themes is the `theming` concern; safe-area
padding is the `touch` concern; stacking order and inert decorative layers are the `web-layout`
concern; image outlines are the `shape-and-depth` concern.

Contents: 1 a worked example, 2 reserve the space, 3 numbers and labels that change, 4 weight that
stays put, 5 persisted state on first paint, 6 late UI, 7 long content.

## 1. A worked example

A recording pill shows a running timer, and the request is:

> the numbers in the recording timer keep jumping around, fix it

The vague prompt gets `font-family: ui-monospace, monospace;`. The precise one, "use tabular-nums
on the recording timer", gets `font-variant-numeric: tabular-nums;`.

Technically, both prompts fix the issue we are pointing at, but we obviously don't want to switch to
a mono font here. With enough experience, you know that using tabular-nums is the right fix here.

The monospace face holds the width too, but it sets the timer in a different face from the label
beside it. Equal-width digits keep the timer in the interface's own font. Section 3 holds the rule.

## 2. Reserve the space before the content arrives

Skeleton loaders, image placeholders, and dynamic content areas get hardcoded dimensions (or
`aspect-ratio`) matching the loaded state. Images always declare their dimensions so the page
doesn't reflow as they arrive. Videos declare theirs the same way. The attributes don't fix the
rendered size. They give the browser the ratio so it reserves the box before the bytes arrive.

Skeletons occupy the same box the loaded content will. Whether a view shows a skeleton or a spinner
is the `states` concern.

```css
.row-skeleton { height: 48px; }   /* the loaded row's height, not a guess */
```

A form's error line works the same way: it is reserved before the error shows, so the page doesn't
jump when it appears (the `forms` concern renders it). Recipe for media whose file you do not
control: `image-box-that-holds-any-upload`.

Hunt for: `<img>`, `<video>` and `<iframe>` with no `width` and `height` or `aspect-ratio`; a value
fetched after mount rendered into the flow with nothing in its place until it lands; skeletons with
a different height or row count than the loaded content; `next/image` with `fill` inside a parent
that has no size; embeds and ad slots.

**Audit: Blocking.** A dynamic number or async value with no reserved space or tabular numbers: it
will shift the layout. Blocking applies where it arrives after first paint and moves content that is
already on screen.

**Audit: Blocking.** Media with no reserved box that lands after first paint above content already
on screen: an image, video, `<iframe>`, embed or ad slot with no dimensions or `aspect-ratio`, or a
`next/image` with `fill` in a parent that has no size, placed in the first viewport.

**Audit: Important.** The same media placed below the first viewport, or a skeleton or placeholder
whose box differs from the loaded content.

Preload fonts so text doesn't reflow when they land:

```jsx
import { preload } from 'react-dom';

preload('/fonts/inter-var.woff2', {
  as: 'font',
  type: 'font/woff2',
  crossOrigin: 'anonymous',
});
// Plain HTML equivalent:
// <link rel="preload" href="/fonts/inter-var.woff2" as="font" type="font/woff2" crossorigin />
```

This is the default for a project with no font-loading strategy of its own; where it has one, that
strategy wins (the `typography` concern leaves font loading to the project). Keep `crossorigin` on
every font preload, a same-origin file included; the pointer says why.

- **Pointer**: React, `preload`, Parameters,
  <https://react.dev/reference/react-dom/preload#parameters>, and MDN, `rel=preload`, "CORS-enabled
  fetches",
  <https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Attributes/rel/preload#cors-enabled_fetches>
- **As of**: 2026-10-29
- **Recheck trigger**: React changes the `preload` options, or MDN changes when a font preload needs
  `crossorigin`.

**Audit: Important.** An above-the-fold webfont with no preload whose arrival reflows visible text,
in a project with no font-loading strategy of its own.

## 3. Numbers and labels that change don't shift the layout

Counters, prices, timers: any dynamic number gets `font-variant-numeric: tabular-nums` so digits
occupy equal width and don't jiggle as they update.

Proportional digits have different widths, so a ticking counter or a price that updates jitters
everything beside it. A button whose label changes from "Save" to "Saving…" changes width and shoves
its neighbors.

```css
.counter, .price, td.numeric { font-variant-numeric: tabular-nums; }
```

Tailwind: `tabular-nums`. Recipe: `tabular-numbers`.

In data tables, right-aligned tabular numbers do the work zebra striping was compensating for. Fix
alignment before adding stripes.

A label that swaps after hydration, such as a marketing call to action that reads "Get Started"
until the client knows the visitor is signed in, needs the same fixed or minimum width. So does a
submit button that changes its label while its request runs (the `forms` concern owns the pending
state itself).

Hunt for: counters, timers, prices, percentages, table number columns, and pagination without
`tabular-nums`; buttons with swapping labels and no fixed or minimum width.

A number that updates in place while on screen (a timer, a counter, a live price) with proportional
digits takes the Blocking tag of section 2.

**Audit: Important.** A button or call to action whose label changes with no fixed or minimum width,
or percentages and pagination that change between views with proportional digits.

## 4. Font weight never changes on interaction

No font-weight change on hover/active/selected: swapping weight reflows the text by a pixel. Use
color, background, or a non-reflowing indicator instead.

```css
/* Bad */
.tab:hover { font-weight: 600; }

/* Good */
.tab { font-weight: 500; }
.tab[aria-selected="true"] { color: var(--gray-12); }
```

Define weights as variables (`--font-weight-normal: 400; --font-weight-medium: 500;
--font-weight-semibold: 600; --font-weight-bold: 700;`) so they're adjustable globally.

The one exception is a variable font whose glyphs keep their width at every weight; when it applies
is the `typography` concern's rule. How a hover transitions, how far a press scales and when
`will-change` helps are the `motion` concern; the focus ring's color is the `color` concern, and
keeping the focus ring visible is the `accessibility` concern; a `::selection` tint is the
`typography` concern.

Hunt for: `font-weight` inside `:hover`, `.active`, `.selected`, `[aria-selected]`,
`[data-state="active"]`; `hover:font-medium`, `data-[state=active]:font-semibold`. The last two are
Tailwind class names to search for.

**Audit: Important.** Font weight that changes on hover or when active: the text reflows by a pixel.
The same holds for a selected or current state (`.active`, `.selected`, `[aria-selected]`,
`[data-state="active"]` on a tab, a nav item or a list row), outside the variable-font exception
above. It is Important, not Blocking: a one-pixel reflow does not break the interaction or the
accessibility floor.

## 5. Persisted state is correct on first paint

The theme that flashes light before going dark, the sidebar that renders open and then snaps shut,
the tab that resets and then jumps to the saved one. Each is a value read in `useEffect` *after* the
first paint.

Interactive components must render their real state on first paint: persist state to
`localStorage`/`sessionStorage`, hydrate correctly under SSR, and set initial state before render,
never default-then-correct.

Fix by where the state lives:

- **Theme**: a blocking inline script in `<head>` that sets the class or `data-theme` before paint.
  `next-themes` does this; the finding is a hand-rolled toggle.
  That is, a toggle with no such script, which sets the theme only after first paint. A script you
  write is a static string with no value interpolated into it: it accepts only the theme names the
  app defines (such as `light`, `dark`, `system`), falls back to the default for anything else, and
  applies the result with `classList` or `setAttribute`, never by writing markup. Under a
  Content-Security-Policy, allow it with a nonce or a hash, never `'unsafe-inline'`.
- **Server-rendered layout state** (sidebar open, density): store it in a cookie and read it on the
  server, so the HTML arrives correct. Parse the cookie to one of the values the app defines, fall
  back to the default otherwise, and never write its raw value into the markup.
- **Client-only state**: `useState(() => readStoredValue())` with a lazy initializer, and render
  nothing size-dependent until it's known.

Hunt for: `useEffect` that reads `localStorage` and then calls a state setter for theme, sidebar,
layout, tab, or density; `dark:` classes applied by a client-only hook; `useState(false)` followed by
an effect that corrects it.

- **Pointer**: next-themes, README, "The Flash",
  <https://github.com/pacocoursey/next-themes#the-flash>
- **As of**: 2026-10-29
- **Recheck trigger**: the README stops saying the provider injects a script that sets the theme
  before the page renders.

- **Pointer**: MDN, `Content-Security-Policy: script-src`, "Unsafe inline script",
  <https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/script-src#unsafe_inline_script>
- **As of**: 2026-10-29
- **Recheck trigger**: that section changes how a nonce or hash allows an inline script, or stops
  recommending them over `'unsafe-inline'`.

**Audit: Important.** Persisted theme, sidebar, layout, tab or density state that renders a default
on first paint and corrects itself after.

## 6. Late UI doesn't push content

Anything that mounts after load and takes up space in the flow moves the page under the user: a
cookie banner, an announcement bar, an "install the app" prompt, a verify-your-email strip.

Hunt for: banners rendered conditionally at the top of the layout after a client-side check.

Fix: overlay it (`position: fixed`, with safe-area padding), or reserve its space from the first
paint by deciding on the server whether it shows. The safe-area padding is the `touch` concern's.

**Audit: Important.** A banner, bar or prompt that mounts after load in the flow and pushes the page
down.

## 7. Long content is handled

The dev data had names like "Test Project". Real data has a 90-character project name, an email with
no break opportunity, and a user whose name is in German.

Hunt for: cards, table cells, sidebar items, breadcrumbs, and avatars-with-names that render
user-generated strings with no `truncate`, `line-clamp`, `min-width: 0`, or `overflow-wrap`.

```css
.cell-text {
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.card-text { overflow-wrap: break-word; }
```

A flex child needs `min-width: 0` before `text-overflow: ellipsis` does anything. Recipe:
`long-text-that-wraps-truncates-or-clamps`.

That truncation needs a way to read the rest (a `title`, a tooltip, an expand control) is the
`typography` concern's rule.

**Audit: Important.** A card, table cell, sidebar item, breadcrumb or name beside an avatar that
renders user-generated text with no wrap, truncation or clamp, so a long value breaks the layout;
or a long URL, token or unbroken word anywhere that can overflow its container. A hero headline
that overflows the viewport is the `marketing-pages` concern's.
