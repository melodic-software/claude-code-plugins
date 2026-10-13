# Layout

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `content-grid-with-breakouts`, `intrinsic-grid`, `subgrid-rows-shared-across-cards`,
`sidebar-that-wraps-on-its-own`, `container-queries-with-container-units`,
`stack-layers-with-grid`, `safe-alignment`, `overflow-clip-over-hidden`.

## Content grid with breakouts: `content-grid-with-breakouts`

Why: one grid on the section replaces the `section > .container` wrapper pair, and any child can
be content width, wider, or edge to edge.

Baseline: [`grid-template-columns`](https://developer.mozilla.org/en-US/docs/Web/CSS/grid-template-columns#browser_compatibility),
[`min()`](https://developer.mozilla.org/en-US/docs/Web/CSS/min#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it wherever you would reach for a centered max-width container: on `main` for flowing content,
or on each section. It suits CMS content: an editor widens a block with one class and no wrapper.

```css
.content-grid {
  --gutter: var(--space-m, 1.5rem);
  --content: 64rem;
  --breakout: 80rem;

  display: grid;
  grid-template-columns:
    [full-width-start] minmax(var(--gutter), 1fr)
    [breakout-start] minmax(0, calc((var(--breakout) - var(--content)) / 2))
    [content-start] min(100% - var(--gutter) * 2, var(--content)) [content-end]
    minmax(0, calc((var(--breakout) - var(--content)) / 2)) [breakout-end]
    minmax(var(--gutter), 1fr) [full-width-end];
}

:is(.content-grid, .full-width) > * { grid-column: content; }
:is(.content-grid, .full-width) > .breakout { grid-column: breakout; }
:is(.content-grid, .full-width) > .full-width {
  grid-column: full-width;
  display: grid;
  grid-template-columns: inherit;
}
```

Rules:

- Every child must be placed. An unplaced child lands in the gutter track.
- Every direct child is a grid item. Wrap a run of inline elements in one element.
- Change a width by overriding `--content`, not by writing a new column template.
- Where the authoring system has no child selectors, each child sets its own `grid-column` to
  `content`, `breakout` or `full-width`; the column template goes wherever the project defines
  reusable styles.

## Intrinsic grid: `intrinsic-grid`

Why: the grid fits as many columns as the width allows, replacing a column count per breakpoint.

Baseline: [`repeat()`](https://developer.mozilla.org/en-US/docs/Web/CSS/repeat#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for any set of equal cards or tiles.

```css
.grid {
  display: grid;
  gap: var(--space-s, 1rem);
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 16rem), 1fr));
}
```

Rules:

- `auto-fit` stretches a short row to fill the width. Use `auto-fill` when the item count changes,
  such as a filtered list, so cards keep their size.

## Subgrid rows shared across cards: `subgrid-rows-shared-across-cards`

Why: card parts (title, body, footer) line up across a row whatever the length of their content.

Baseline: [`subgrid`](https://developer.mozilla.org/en-US/docs/Web/CSS/grid-template-rows#browser_compatibility).
As of 2026-10-11, recheck on a status change.

```css
.cards {
  display: grid;
  gap: 1.5rem;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 16rem), 1fr));
}

.card {
  display: grid;
  grid-row: span 3;
  grid-template-rows: subgrid;
  row-gap: 0.5rem;
}
```

Rules:

- The span must equal the number of parts in the card. Without `grid-row: span N` every part piles
  into one row.
- Set `row-gap` on the card, or it inherits the parent's gap between its parts.

## Sidebar that wraps on its own: `sidebar-that-wraps-on-its-own`

Why: the pair stacks when the main side would drop below a share of the container, with no media
query.

Baseline: [`gap` in flex layout](https://developer.mozilla.org/en-US/docs/Web/CSS/gap#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for any pair where one side has an ideal width and the other takes the rest: a media
object, an input with a button, a page with an aside.

```css
.with-sidebar {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem;
}

.sidebar {
  flex-basis: 20rem;
  flex-grow: 1;
}

.main {
  flex-basis: 0;
  flex-grow: 999;
  min-inline-size: 50%;
}
```

Rules:

- The wrap point is a share of the container, not a length. Change `min-inline-size` to move it.
- Drop the sidebar's `flex-basis` for a sidebar sized by its content.
- For a sticky sidebar, add `align-self: start` beside `position: sticky` and its inset. A
  stretched sidebar has no room to stick.
- A bare `img` or `video` as one side stretches to the row height and distorts. Set
  `align-items: start` on the container.

## Container queries with container units: `container-queries-with-container-units`

Why: the component responds to the slot it is given, where a media query only knows the viewport.

Baseline: [`@container`](https://developer.mozilla.org/en-US/docs/Web/CSS/@container#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for any component that appears in slots of different widths.

```css
.slot { container-type: inline-size; }

.card h2 { font-size: clamp(1.25rem, 1rem + 2cqi, 2rem); }

@container (width > 30rem) {
  .card {
    display: grid;
    grid-template-columns: 12rem 1fr;
  }
}
```

Rules:

- The container must be an ancestor. An element cannot query itself.
- A container cannot take its width from its content. Never put `container-type` on a
  shrink-to-fit element, or it collapses to zero.
- With no container ancestor the query never matches. Making `header`, `main` and `footer`
  containers in the base stylesheet covers most components.
- A container cannot also be a subgrid; `subgrid-rows-shared-across-cards` and this technique need
  separate elements.
- Container units differ from queries: with no container above, `cqi` measures the viewport, so
  one `cqi` token serves the page and every slot.
- Never register a fluid `cqi` token with `@property`. A registered length computes once on
  `:root`, where there is no container, and every slot gets the viewport's value.

## Stack layers with grid: `stack-layers-with-grid`

Why: layers share one grid cell and size the container together, replacing `position: absolute`
with its offsets, sizes and transforms.

Baseline: [`grid-area`](https://developer.mozilla.org/en-US/docs/Web/CSS/grid-area#browser_compatibility),
[`place-self`](https://developer.mozilla.org/en-US/docs/Web/CSS/place-self#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it whenever things sit on top of each other: text over an image, a badge on a card, two icons
that swap.

```css
.stack { display: grid; }
.stack > * { grid-area: 1 / 1; }

.stack > .title { place-self: center; }
.stack > .badge { place-self: start end; }
```

Rules:

- A layer later in the DOM paints on top. Use `z-index` only to change that order.
- Keep `position: absolute` for a layer that must not affect the container's size.

## Safe alignment: `safe-alignment`

Why: `safe` falls back to start alignment when content overflows, so nothing is pushed off the
unreachable edge.

Baseline: [`justify-content`](https://developer.mozilla.org/en-US/docs/Web/CSS/justify-content#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it wherever content is centered or end-aligned in a container that can become too small: a
tab row, a toolbar, a vertically centered modal.

```css
.tabs {
  display: flex;
  overflow-x: auto;
  justify-content: safe center;
}
```

Rules:

- It works on every `align-*`, `justify-*` and `place-*` property.
- Auto margins on the item center it the same way and are safe wherever flexbox works:
  `push-one-item-away-with-an-auto-margin` (`spacing-and-shape.md`).

## `overflow: clip` over `hidden`: `overflow-clip-over-hidden`

Why: `clip` cuts overflow without making a scroll container, so `position: sticky` inside keeps
working and nothing can scroll by accident.

Baseline: [`overflow`](https://developer.mozilla.org/en-US/docs/Web/CSS/overflow#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it whenever you want to cut off overflow and do not need scrolling.

```css
.hero { overflow-x: clip; }
```

Rules:

- Put it on the element that overflows, not on `html` or `body`.
- Keep `hidden` or `auto` for elements a script scrolls; `clip` blocks that too.
- Keep `hidden` or `auto` on an element with `resize`; with `clip` no resize handle is drawn.
