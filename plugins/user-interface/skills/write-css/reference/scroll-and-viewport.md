# Scroll and viewport

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `carousel-on-native-scroll`, `scroll-area-between-a-fixed-header-and-footer`,
`styles-that-apply-only-when-a-scroller-overflows`, `anchor-targets-that-clear-a-sticky-header`,
`no-rubber-band-bounce-on-desktop`, `content-clear-of-the-notch`,
`full-height-that-browser-chrome-cannot-cover`, `gesture-surface-that-claims-only-its-axis`,
`nothing-wider-than-the-viewport`, `scrollbars-styled-only-inside-small-scrollers`,
`menu-items-that-fade-at-the-container-edge`.

## Carousel on native scroll: `carousel-on-native-scroll`

Why: the carousel is a real scroll container, so swipe, trackpad, keyboard and momentum work before
any script loads.

Baseline: [`scroll-snap-type`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scroll-snap-type#browser_compatibility),
[`::scroll-button()`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/::scroll-button#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for any horizontal row of cards.

```css
.carousel {
  display: flex;
  gap: var(--space-s, 1rem);
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  scroll-padding-inline: var(--gutter, 1.5rem);
  padding-inline: var(--gutter, 1.5rem);
  overscroll-behavior-x: contain;
  scrollbar-width: none;
}

.carousel > * {
  flex: none;
  scroll-snap-align: start;
}

@media (prefers-reduced-motion: no-preference) {
  .carousel { scroll-behavior: smooth; }
}
```

Arrow buttons are the one part that needs a script. `scrollBy()` can only scroll the carousel,
never the page.

```html
<button data-carousel-dir="-1" aria-label="Previous">←</button>
<button data-carousel-dir="1" aria-label="Next">→</button>
```

```js
const carousel = document.querySelector(".carousel");
const [prev, next] = document.querySelectorAll("[data-carousel-dir]");
const sign = getComputedStyle(carousel).direction === "rtl" ? -1 : 1;

const step = (dir) => {
  const card = carousel.firstElementChild.getBoundingClientRect().width;
  carousel.scrollBy({ left: sign * dir * card });
};

const sync = () => {
  const max = carousel.scrollWidth - carousel.clientWidth;
  const scrolled = Math.abs(carousel.scrollLeft);
  prev.disabled = scrolled <= 1;
  next.disabled = scrolled >= max - 1;
};

prev.addEventListener("click", () => step(-1));
next.addEventListener("click", () => step(1));
carousel.addEventListener("scroll", sync, { passive: true });
sync();
```

Rules:

- Never move slides with `transform`, and never handle wheel or touch events yourself.
- Match `scroll-padding-inline` to `padding-inline` so a snapped card lines up with page content.
- CSS-drawn arrows and dots (`::scroll-button()`, `::scroll-marker`) can replace the script only
  where the target supports them; check their compat entries first.

## Scroll area between a fixed header and footer: `scroll-area-between-a-fixed-header-and-footer`

Why: the panel grows with its content up to a limit, then only the middle scrolls while header and
footer stay put.

Baseline: [`scrollbar-gutter`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scrollbar-gutter#browser_compatibility),
[`overscroll-behavior`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/overscroll-behavior#browser_compatibility),
[`dvh`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/length#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for the body of a modal, a chat list, a drawer or a sidebar.

```css
.panel {
  display: flex;
  flex-direction: column;
  max-block-size: 80dvh;
}

.panel-body {
  flex: 1;
  overflow-y: auto;
  overscroll-behavior: contain;
  scrollbar-gutter: stable;
}

.panel-wrap {
  flex: 1;
  min-block-size: 0;
  display: flex;
  flex-direction: column;
}
```

Rules:

- The panel needs a limit, `max-block-size` or a height. With no limit nothing overflows.
- `.panel-wrap` is only for an element between the panel and the body. Leave it out when the body
  is a direct child.
- A header or footer with a set height shrinks when the body overflows. Give it `flex: none`, or
  size it with padding.
- Keep `min-height: 0` out of the reset. On every element it lets each item of a fixed-height
  column shrink under its own text.
- The gutter takes the scrollbar's width on a short list as well. That is the price of no shift.

## Styles that apply only when a scroller overflows: `styles-that-apply-only-when-a-scroller-overflows`

Why: a scroll timeline only runs when there is something to scroll, so the edges fade only then,
replacing a `ResizeObserver` comparing `scrollWidth` with `clientWidth`.

Baseline: [`animation-timeline`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/animation-timeline#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on any row that may or may not fit: tabs, a toolbar, a table wrapper.

A fade over a scrollable list restricts the viewable area and cuts off content the user is
scrolling to read. A fade on a scroller is allowed only on these terms:

- Never fade a scroller statically. The fade exists only while there is more to scroll.
- Clear each edge where no content remains: the start edge is sharp at the start, the end edge at
  the end.
- Never make the fade the only scroll cue. Keep a scrollbar, a partly visible next item or an
  arrow beside it.
- Keep focus rings outside the masked band, so a focused item at the edge is not faded with it.

Register the two lengths and give the keyframes different ends, so only the side that still has
content fades:

```css
@property --fade-start {
  syntax: "<length>";
  inherits: false;
  initial-value: 0px;
}

@property --fade-end {
  syntax: "<length>";
  inherits: false;
  initial-value: 0px;
}

@keyframes edges {
  from { --fade-start: 0px; --fade-end: 2rem; }
  10%, 90% { --fade-start: 2rem; --fade-end: 2rem; }
  to { --fade-start: 2rem; --fade-end: 0px; }
}

.scroller-edges {
  overflow-x: auto;
  animation: edges linear;
  animation-timeline: scroll(self inline);
  mask-image: linear-gradient(
    to right,
    transparent,
    oklch(0 0 none) var(--fade-start),
    oklch(0 0 none) calc(100% - var(--fade-end)),
    transparent
  );
}
```

Rules:

- Write `animation-timeline` after `animation`. The shorthand resets the timeline.
- Declare the default outside the keyframes, as the `initial-value` of each `@property` does here.
- Any value can go in the keyframes, keywords included, such as flipping a row to `row-reverse`
  when it overflows.
- Write no fallback. Without scroll timelines the row scrolls without the fade.
- Gradient directions have no logical keyword, so `to right` stays physical: for right-to-left
  text, repeat the `mask-image` with `to left` in a `:dir(rtl)` rule.

## Anchor targets that clear a sticky header: `anchor-targets-that-clear-a-sticky-header`

Why: scroll padding stops an in-page link target from landing under a fixed or sticky header.

Baseline: [`scroll-padding-block-start`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scroll-padding-block-start#browser_compatibility),
[`scroll-margin-block-start`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scroll-margin-block-start#browser_compatibility).
As of 2026-10-29, recheck on a status change.

Use it on any page with in-page links and a fixed or sticky header.

```css
html { scroll-padding-block-start: var(--header-height, 4rem); }

@media (prefers-reduced-motion: no-preference) {
  html { scroll-behavior: smooth; }
}
```

The same offset can sit on the targets instead, where one page's header differs from the rest:

```css
[id] { scroll-margin-block-start: var(--header-height, 4rem); } /* the sticky header's height */
```

Rules:

- Keep the offset outside the motion query, so people who ask for reduced motion still get it.
- Tie the value to the header's height: share one custom property between the two. Read the height
  from the code, never guess it.

## No rubber-band bounce on desktop: `no-rubber-band-bounce-on-desktop`

Why: on a desktop trackpad the page overscroll stretches the whole page past its edge and drags
fixed UI along; turning it off keeps app-like pages still.

Baseline: [`overscroll-behavior`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/overscroll-behavior#browser_compatibility),
[`any-pointer`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/At-rules/@media/any-pointer#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on app-like pages with fixed UI, such as a sidebar or a sticky header.

```css
html { overscroll-behavior-y: none; }

@media (any-pointer: coarse) {
  html { overscroll-behavior-y: auto; }
}
```

Rules:

- Set it on `html`. The viewport takes its overscroll behavior from the root element.
- Use the `-y` longhand. `overscroll-behavior-x: none` also turns off swipe to go back.
- Give inner scroll containers, such as a sheet, a chat list or a sidebar,
  `overscroll-behavior: contain`. They keep their own bounce and stop the page behind them moving.
  Never use a `touchmove` listener with `preventDefault()` for this.
- The coarse-pointer reset is for a scrolling document, where pull-to-refresh is welcome on a
  phone. An app shell with its own scroll areas, a drawer the user drags down or a canvas keeps
  `none` at every pointer type, and leaves out the `@media (any-pointer: coarse)` block.

```css
/* App shell: no page bounce or pull-to-refresh on any device */
html, body { overscroll-behavior-y: none; }

.sheet-content {
  overflow-y: auto;
  overscroll-behavior: contain;
}
```

## Content clear of the notch: `content-clear-of-the-notch`

Why: safe-area insets keep fixed bars and sheets out from under a phone's notch and home
indicator.

Baseline: [`env()`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/env#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on fixed headers, bottom bars, toasts and sheets in anything that should feel like an app on
a phone. Add `viewport-fit=cover` to the viewport meta tag, then pad those elements by the
insets.

```css
.app-header { padding-block-start: env(safe-area-inset-top, 0px); }

.bottom-bar { padding-block-end: env(safe-area-inset-bottom, 0px); }

.sheet { padding-block-end: calc(1rem + env(safe-area-inset-bottom, 0px)); }

/* Landscape puts the notch on the side */
.sidebar { padding-inline-start: env(safe-area-inset-left, 0px); }
.sidebar:dir(rtl) { padding-inline-start: env(safe-area-inset-right, 0px); }

.form-scroll { padding-block-end: calc(var(--cta-height) + env(safe-area-inset-bottom, 0px)); }
```

Rules:

- Without `viewport-fit=cover` every inset is `0px` and the padding does nothing.
- Give `env()` a fallback of `0px` wherever it sits inside `calc()`.
- Normal page content needs none of this. The header's padding covers it.
- `.form-scroll` is the scroll container under a fixed bottom CTA: padding it by the CTA's height
  plus the inset lets the last field scroll clear of the CTA.
- The insets are physical: `safe-area-inset-left` stays on the left in right-to-left text, so the
  `:dir(rtl)` rule takes the right inset for the sidebar's start side.

## Full height that browser chrome cannot cover: `full-height-that-browser-chrome-cannot-cover`

Why: `100vh` is the tallest the viewport gets, so on a phone with the URL bar showing it overflows
and a bottom-pinned control sits under the bar.

Baseline: [`dvh`, `svh`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Values/length#browser_compatibility).
As of 2026-10-29, recheck on a status change.

Use it on app shells, drawers, heroes and first screens.

```css
/* App shell, drawers, anything that should track the visible area as chrome shows/hides */
.app { height: 100dvh; }

/* Heroes and first screens: the smallest the viewport gets, so nothing is ever cut off */
.hero { min-height: 100svh; }
```

Rules:

- In Tailwind: `h-dvh`, `min-h-svh`; `h-screen` and `min-h-screen` are `100vh` and carry the bug.
  The class names are search tokens: confirm what each compiles to in the pointer below.
- Keep a `100vh` fallback line above only if the project's support matrix demands it.
- `dvh` on a marketing hero shifts the layout as the URL bar collapses mid-scroll; heroes take
  `svh`.

- **Pointer**: Tailwind CSS, `height` and `min-height`, "Quick reference",
  <https://tailwindcss.com/docs/height#quick-reference> and
  <https://tailwindcss.com/docs/min-height#quick-reference>
- **As of**: 2026-10-29
- **Recheck trigger**: Tailwind renames these classes or changes the unit one compiles to.

## Gesture surface that claims only its axis: `gesture-surface-that-claims-only-its-axis`

Why: `touch-action` tells the browser which pans it keeps, so a swipe on a carousel or a drag on a
sheet no longer also scrolls the page.

Baseline: [`touch-action`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/touch-action#browser_compatibility).
As of 2026-10-29, recheck on a status change.

Use it on any element with a hand-built gesture: a carousel driven by script, a drag-to-dismiss
sheet, a slider, a canvas.

```css
.carousel {
  touch-action: pan-y; /* the carousel handles horizontal; the browser keeps vertical */
}
.drag-surface {
  touch-action: none;  /* a custom gesture (a drag-to-dismiss sheet, a slider, a canvas) owns every axis */
}
.vertical-sheet-handle {
  touch-action: pan-x; /* the sheet handles vertical drags; horizontal stays with the browser */
}
```

Rules:

- The value names what the browser may still do, not what the element handles.
- `none` only on an element that handles every direction itself, or the user cannot scroll past
  it.
- A carousel on native scroll needs none of this: `carousel-on-native-scroll`.

## Nothing wider than the viewport: `nothing-wider-than-the-viewport`

Why: one element wider than the viewport makes the whole page pan sideways on a phone.

Baseline: [`overflow-wrap`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/overflow-wrap#browser_compatibility).
As of 2026-10-29, recheck on a status change.

Use it on cards with user text, `<pre>` blocks, tables and anything with a fixed width.

```css
.card-text { overflow-wrap: break-word; }
.table-wrap, pre { overflow-x: auto; }
```

Rules:

- Fix the element that overflows. `overflow-x: hidden` on `body` hides the symptom and breaks
  `position: sticky`.
- `the-reset` sets `overflow-wrap: break-word` on `:root`; a component that resets it needs it
  back.
- Use `100%`, not `100vw`, for full-width elements: `100vw` includes the vertical scrollbar and
  overflows by its width.
- Give a wide table a scrolling wrapper rather than shrinking its text.

## Scrollbars styled only inside small scrollers: `scrollbars-styled-only-inside-small-scrollers`

Why: the page's own scrollbar is the one people know; a styled one inside a small element, such as
a code block, matches it to the surface without replacing the page's.

Baseline: [`::-webkit-scrollbar`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Selectors/::-webkit-scrollbar#browser_compatibility),
[`scrollbar-color`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/scrollbar-color#browser_compatibility).
As of 2026-10-29, recheck on a status change.

Never replace the page scrollbar. Customize scrollbars only inside small elements like code blocks:
`8px` wide, `rgba(0,0,0,0.2)` thumb, `4px` radius.

Write that thumb as `oklch(0 0 none / 0.2)`: colors here are `oklch()` with `none` as the hue of a
gray, never a hardcoded `rgba()` (`oklch-color`, `foundations.md`).

```css
.code-block::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}
.code-block::-webkit-scrollbar-thumb {
  background: oklch(0 0 none / 0.2);
  border-radius: 4px;
}
```

Rules:

- `scrollbar-width` and `scrollbar-color` are the standard properties; check the target's compat
  rows before writing them beside or in place of the prefixed rules.
- In a dark theme the thumb takes the light form, `oklch(1 0 none / 0.2)`.

## Menu items that fade at the container edge: `menu-items-that-fade-at-the-container-edge`

Why: when items animate past their container's edge and `overflow: hidden` would break the
animation, a mask fades them out at the edge instead of clipping the whole container.

Baseline: [`mask-image`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/mask-image#browser_compatibility).
As of 2026-10-29, recheck on a status change.

Use it on a menu, tab panel or carousel whose items slide in and out while something else inside
must stay unclipped.

```css
.menu-viewport {
  mask-image: linear-gradient(
    to right,
    transparent,
    oklch(0 0 none) var(--edge, 1rem),
    oklch(0 0 none) calc(100% - var(--edge, 1rem)),
    transparent
  );
}
```

Rules:

- Keep the fade band inside the container's padding, so items at rest are never faded.
- Put the mask on the layer the items move in, not on the panel, so the panel's own shadow and
  border stay sharp.
- Gradient directions have no logical keyword: for right-to-left text, repeat the `mask-image` with
  `to left` in a `:dir(rtl)` rule.
