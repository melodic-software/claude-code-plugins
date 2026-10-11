# Motion

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `opt-in-motion`, `motion-tokens`, `transition-a-custom-property-with-property`,
`shadow-change-that-fades-and-does-not-repaint`, `cross-document-view-transitions`,
`indicator-that-slides-to-the-active-item`.

## Opt-in motion: `opt-in-motion`

Why: movement is added only for people who have not asked to reduce motion, instead of stripped
afterwards.

Baseline: [`prefers-reduced-motion`](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-reduced-motion#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for every transition or animation that moves or scales something.

```css
@media (hover: hover) and (pointer: fine) {
  .box:hover { transform: scale(1.2); }
}

@media (prefers-reduced-motion: no-preference) {
  .box { transition: transform 200ms var(--ease-out, ease-out); }
}
```

Rules:

- Build the state change first and add the motion inside the query. Do not strip motion afterwards
  with a global rule that sets every duration to `0.01ms`.
- Fades of opacity and color are not motion and can stay outside the query.
- Animation driven by a script checks the same query with `matchMedia`.

## Motion tokens: `motion-tokens`

Why: easing curves defined once and a duration per role make every transition feel like one
system.

Baseline: [`cubic-bezier()`](https://developer.mozilla.org/en-US/docs/Web/CSS/easing-function#browser_compatibility),
widely available. As of 2026-10-11, recheck on a status change.

Use them in every transition and animation. The values come from the resolved config, never from
this file: `config.values.animation.easing` holds each curve as four control points, written as the
arguments of `cubic-bezier()`, and `config.values.animation.duration_ms` holds the longest duration
for each role. The project's own easing and duration tokens beat both.

```css
:root {
  --ease-out: cubic-bezier(<animation.easing.out>);
  --ease-in-out: cubic-bezier(<animation.easing.in_out>);
  --duration-medium: <animation.duration_ms.medium>ms;
}

.dropdown { transition: opacity var(--duration-medium) var(--ease-out); }
```

Rules:

- Never use `ease-in` on UI. It starts slow and reads as lag.
- `out` is for anything entering or leaving, `in_out` for something already on screen that moves
  or morphs, and `drawer` for a drawer or sheet.
- Keep each transition within its role: `press` for press feedback, `small` for tooltips and small
  popovers, `medium` for dropdowns and menus, `large` for modals, dialogs, drawers and sheets.
  Small, frequent UI sits near the short end of its role.
- Name the properties in a transition. Never write `transition: all`.
- Other techniques write `var(--ease-out, ease-out)`, so their snippets work before these tokens
  exist.
- Whether something should animate at all is a design question, not a CSS one; add no motion
  beyond what the task calls for. `/user-interface:write-animation` owns that question.

## Transition a custom property with `@property`: `transition-a-custom-property-with-property`

Why: a registered property interpolates, so one state change drives several values together and a
number fed in by a script eases in CSS.

Baseline: [`@property`](https://developer.mozilla.org/en-US/docs/Web/CSS/@property#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it when one state change should drive several values, or a script feeds a number such as
pointer position or progress into CSS.

```css
@property --progress {
  syntax: "<number>";
  inherits: true;
  initial-value: 0;
}

.card:focus-within { --progress: 1; }

@media (hover: hover) and (pointer: fine) {
  .card:hover { --progress: 1; }
}

.card .icon {
  display: inline-block;
  rotate: calc(var(--progress) * 90deg);
}

.card .bar {
  transform-origin: left;
  scale: calc(0.25 + var(--progress) * 0.75) 1;
}

.card .bar:dir(rtl) { transform-origin: right; }

.card .more { opacity: var(--progress); }

@media (prefers-reduced-motion: no-preference) {
  .card { transition: --progress 0.25s var(--ease-out, ease-out); }
}
```

Rules:

- `initial-value` is required for every syntax except `"*"`.
- `rotate`, `scale` and `translate` do nothing on an inline element. Give it `display: inline-block`
  or another box type first.
- A registration is global. Register each name once and keep names specific.
- A script only writes the variable, as in `el.style.setProperty("--x", "40%")`. Easing and
  duration stay in CSS.
- Other useful types: `<length-percentage>` for a gradient position, `<angle>` for a conic
  gradient.

## Shadow change that fades and does not repaint: `shadow-change-that-fades-and-does-not-repaint`

Why: fading the opacity of two pre-drawn shadows is composited, where animating `box-shadow`
repaints every frame.

Baseline: [`opacity`](https://developer.mozilla.org/en-US/docs/Web/CSS/opacity#browser_compatibility),
widely available. As of 2026-10-11, recheck on a status change.

Use it on cards that lift on hover, most of all in a grid of many cards or with a large blur.

```css
.card {
  position: relative;
  isolation: isolate;
}

.card::before,
.card::after {
  content: "";
  position: absolute;
  inset: 0;
  z-index: -1;
  border-radius: inherit;
  pointer-events: none;
}

.card::before { box-shadow: var(--shadow-rest); }

.card::after {
  box-shadow: var(--shadow-lifted);
  opacity: 0;
}

@media (hover: hover) and (pointer: fine) {
  .card:hover::before { opacity: 0; }
  .card:hover::after { opacity: 1; }
}

@media (prefers-reduced-motion: no-preference) {
  .card::before,
  .card::after { transition: opacity 0.25s var(--ease-out, ease-out); }
}
```

Rules:

- The card needs its own background. The pseudo-elements have none.
- It uses both pseudo-elements. `hit-area-larger-than-the-visual` and
  `whole-card-clickable-from-one-link` (`interaction.md`) use `::after`, so do not combine them on
  one element.
- For a single small element, transition `box-shadow` directly; the saving is small per card.

## Cross-document view transitions: `cross-document-view-transitions`

Why: two lines crossfade between pages of a multi-page site, replacing a client-side router or a
page-transition script.

Baseline: [`@view-transition`](https://developer.mozilla.org/en-US/docs/Web/CSS/@view-transition#browser_compatibility).
As of 2026-10-11, recheck on a status change.

```css
@view-transition { navigation: auto; }
```

Rules:

- Both pages must include the rule.
- The default crossfade adds no movement and needs no reduced-motion guard. Put added slides inside
  `@media (prefers-reduced-motion: no-preference)`.
- Where unsupported, the browser navigates as normal; write no fallback.

## Indicator that slides to the active item: `indicator-that-slides-to-the-active-item`

Why: anchor positioning places the bar under the active item, replacing a script that measures it
and writes a `transform` and a width.

Baseline: [`anchor-name`](https://developer.mozilla.org/en-US/docs/Web/CSS/anchor-name#browser_compatibility),
[`anchor-scope`](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/anchor-scope#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for the underline on a tab row or the bar beside a side nav.

```html
<nav class="tabs">
  <ul>
    <li><a href="/overview" aria-current="page">Overview</a></li>
    <li><a href="/pricing">Pricing and billing</a></li>
    <li><a href="/docs">Docs</a></li>
  </ul>
</nav>
```

```css
.tabs { anchor-scope: --active; }

.tabs ul {
  position: relative;
  display: flex;
}

.tabs [aria-current="page"] { anchor-name: --active; }

.tabs ul::after {
  content: "";
  position: absolute;
  position-anchor: --active;
  inset-block-end: 0;
  inset-inline-start: anchor(start);
  inline-size: anchor-size(inline);
  block-size: 2px;
  background: currentColor;
}

@media (prefers-reduced-motion: no-preference) {
  .tabs ul::after {
    transition:
      inset-inline-start 0.25s var(--ease-out, ease-out),
      inline-size 0.25s var(--ease-out, ease-out);
  }
}
```

Rules:

- Keep `anchor-scope` on the component root. Without it an anchor name is global, and two navs on
  one page both follow the last active item.
- The list needs `position: relative`, so the bar is positioned against the box holding the items.
- For a vertical list swap the axes: `inset-block-start: anchor(start)` and
  `block-size: anchor-size(block)`, and transition those two.
- Give the active item a second cue such as weight or color. Without anchor positioning the
  `anchor()` declarations drop and the bar has no width. Whether an engine slides the bar or only
  places it is read from the compat entries this section links.
