# Scroll and viewport

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `carousel-on-native-scroll`, `scroll-area-between-a-fixed-header-and-footer`,
`styles-that-apply-only-when-a-scroller-overflows`, `anchor-targets-that-clear-a-sticky-header`,
`no-rubber-band-bounce-on-desktop`, `content-clear-of-the-notch`.

## Carousel on native scroll: `carousel-on-native-scroll`

Why: the carousel is a real scroll container, so swipe, trackpad, keyboard and momentum work before
any script loads.

Baseline: [`scroll-snap-type`](https://developer.mozilla.org/en-US/docs/Web/CSS/scroll-snap-type#browser_compatibility),
[`::scroll-button()`](https://developer.mozilla.org/en-US/docs/Web/CSS/::scroll-button#browser_compatibility).
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

Baseline: [`scrollbar-gutter`](https://developer.mozilla.org/en-US/docs/Web/CSS/scrollbar-gutter#browser_compatibility),
[`overscroll-behavior`](https://developer.mozilla.org/en-US/docs/Web/CSS/overscroll-behavior#browser_compatibility),
[`dvh`](https://developer.mozilla.org/en-US/docs/Web/CSS/length#browser_compatibility).
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

Baseline: [`animation-timeline`](https://developer.mozilla.org/en-US/docs/Web/CSS/animation-timeline#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on any row that may or may not fit: tabs, a toolbar, a table wrapper.

```css
@keyframes overflowing {
  from, to { --fade: 2rem; }
}

.scroller {
  --fade: 0px;
  overflow-x: auto;
  animation: overflowing linear;
  animation-timeline: scroll(self inline);
  mask-image: linear-gradient(
    to right,
    transparent,
    #000 var(--fade),
    #000 calc(100% - var(--fade)),
    transparent
  );
}
```

To fade only the side that still has content, register the two lengths and give the keyframes
different ends:

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
    #000 var(--fade-start),
    #000 calc(100% - var(--fade-end)),
    transparent
  );
}
```

Rules:

- Write `animation-timeline` after `animation`. The shorthand resets the timeline.
- Declare the default outside the keyframes, as `--fade: 0px` does here.
- Any value can go in the keyframes, keywords included, such as flipping a row to `row-reverse`
  when it overflows.
- Write no fallback. Without scroll timelines the row scrolls without the fade.
- Gradient directions have no logical keyword, so `to right` stays physical: for right-to-left
  text, repeat the `mask-image` with `to left` in a `:dir(rtl)` rule.

## Anchor targets that clear a sticky header: `anchor-targets-that-clear-a-sticky-header`

Why: scroll padding stops an in-page link target from landing under a fixed or sticky header.

Baseline: [`scroll-padding`](https://developer.mozilla.org/en-US/docs/Web/CSS/scroll-padding#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on any page with in-page links and a fixed or sticky header.

```css
html { scroll-padding-block-start: var(--header-height, 5rem); }

@media (prefers-reduced-motion: no-preference) {
  html { scroll-behavior: smooth; }
}
```

Rules:

- Keep the offset outside the motion query, so people who ask for reduced motion still get it.
- Tie the value to the header's height: share one custom property between the two.

## No rubber-band bounce on desktop: `no-rubber-band-bounce-on-desktop`

Why: on a desktop trackpad the page overscroll stretches the whole page past its edge and drags
fixed UI along; turning it off keeps app-like pages still.

Baseline: [`overscroll-behavior`](https://developer.mozilla.org/en-US/docs/Web/CSS/overscroll-behavior#browser_compatibility),
[`any-pointer`](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/any-pointer#browser_compatibility).
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

## Content clear of the notch: `content-clear-of-the-notch`

Why: safe-area insets keep fixed bars and sheets out from under a phone's notch and home
indicator.

Baseline: [`env()`](https://developer.mozilla.org/en-US/docs/Web/CSS/env#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on fixed headers, bottom bars, toasts and sheets in anything that should feel like an app on
a phone. Add `viewport-fit=cover` to the viewport meta tag, then pad those elements by the
insets.

```css
.app-header { padding-block-start: env(safe-area-inset-top, 0px); }

.bottom-bar { padding-block-end: env(safe-area-inset-bottom, 0px); }

.sheet { padding-block-end: calc(1rem + env(safe-area-inset-bottom, 0px)); }
```

Rules:

- Without `viewport-fit=cover` every inset is `0px` and the padding does nothing.
- Give `env()` a fallback of `0px` wherever it sits inside `calc()`.
- Normal page content needs none of this. The header's padding covers it.
