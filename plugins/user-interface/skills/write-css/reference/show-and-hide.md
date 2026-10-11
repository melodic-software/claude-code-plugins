# Show and hide

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `enter-and-exit-transitions-from-display-none`, `popover-anchored-to-its-trigger`,
`accordion-that-animates-its-height`, `reveal-with-clip-path`.

## Enter and exit transitions from `display: none`: `enter-and-exit-transitions-from-display-none`

Why: `@starting-style` and discrete transitions animate an element in and out of `display: none`,
replacing a script that adds classes and waits for `transitionend`.

Baseline: [`@starting-style`](https://developer.mozilla.org/en-US/docs/Web/CSS/@starting-style#browser_compatibility),
[`transition-behavior`](https://developer.mozilla.org/en-US/docs/Web/CSS/transition-behavior#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for dialogs, popovers and anything else toggled with `display`.

```css
dialog,
[popover] {
  opacity: 0;
  transition:
    opacity 0.2s var(--ease-out, ease-out),
    display 0.2s allow-discrete,
    overlay 0.2s allow-discrete;
}

dialog::backdrop {
  opacity: 0;
  transition:
    opacity 0.2s var(--ease-out, ease-out),
    display 0.2s allow-discrete,
    overlay 0.2s allow-discrete;
}

dialog[open],
dialog[open]::backdrop { opacity: 1; }

[popover]:popover-open { opacity: 1; }

@starting-style {
  dialog[open],
  [popover]:popover-open,
  dialog[open]::backdrop { opacity: 0; }
}

@media (prefers-reduced-motion: no-preference) {
  dialog,
  [popover] {
    translate: 0 0.5rem;
    transition:
      opacity 0.2s var(--ease-out, ease-out),
      translate 0.2s var(--ease-out, ease-out),
      display 0.2s allow-discrete,
      overlay 0.2s allow-discrete;
  }

  dialog[open] { translate: 0 0; }

  [popover]:popover-open { translate: 0 0; }

  @starting-style {
    dialog[open],
    [popover]:popover-open { translate: 0 0.5rem; }
  }
}
```

Rules:

- Put `@starting-style` after the open-state rule. It has no extra weight in the cascade.
- Never start from `scale(0)`. If the element scales in, start at `scale(0.95)` with `opacity: 0`.
- The `::backdrop` needs the same three states and its own transition, or it snaps while the dialog
  fades.
- Write no fallback: where the exit is unsupported the element closes at once, which is acceptable.
  Which engines animate the exit is read live from the `transition-behavior` and `@starting-style`
  compat entries above. As of 2026-10-11; recheck when either entry's Baseline status changes.
- Keep `[popover]:popover-open` out of the selector list that opens the dialog: a browser that does
  not know one selector drops the whole rule, and the dialog opens at `opacity: 0`. Inside
  `@starting-style` the shared list is safe, because every browser that reads the block knows the
  selector.

## Popover anchored to its trigger: `popover-anchored-to-its-trigger`

Why: the popover positions itself against its trigger and flips at the viewport edge, replacing a
positioning library or a script reading `getBoundingClientRect()`.

Baseline: [`position-area`](https://developer.mozilla.org/en-US/docs/Web/CSS/position-area#browser_compatibility),
[`position-try-fallbacks`](https://developer.mozilla.org/en-US/docs/Web/CSS/position-try-fallbacks#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for dropdown menus and other popovers opened by a click.

```html
<button popovertarget="menu">Options</button>
<div id="menu" popover>
  <button>Rename</button>
  <button>Delete</button>
</div>
```

```css
@supports (position-area: block-end) {
  [popover] {
    margin: 0;
    margin-block-start: 0.5rem;
    position-area: block-end span-inline-end;
    position-try-fallbacks: flip-block, flip-inline, flip-block flip-inline;
  }
}
```

Rules:

- Use `span-*` values, not `center`: `center` stops the flips when the popover is wider than its
  grid cell.
- `margin-block-start` is the gap between trigger and popover. The flip mirrors it, so the gap stays
  on the trigger's side.
- A popover opened by a script has no anchor and lands in the top-left corner. Pass the trigger, as
  in `menu.showPopover({ source: button })`.
- Write no fallback. Without support the `@supports` block is skipped and the popover opens
  centered in the viewport.

## Accordion that animates its height: `accordion-that-animates-its-height`

Why: `<details>` already gives the toggle, keyboard support and find-in-page; these rules animate
open and close with no JavaScript.

Baseline: [`::details-content`](https://developer.mozilla.org/en-US/docs/Web/CSS/::details-content#browser_compatibility),
[`interpolate-size`](https://developer.mozilla.org/en-US/docs/Web/CSS/interpolate-size#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for FAQs and any other disclosure.

```css
:root { interpolate-size: allow-keywords; }

details::details-content {
  height: 0;
  overflow: clip;
}

details[open]::details-content { height: auto; }

@media (prefers-reduced-motion: no-preference) {
  details::details-content {
    transition:
      height 0.3s var(--ease-out, ease-out),
      content-visibility 0.3s allow-discrete;
  }
}
```

Rules:

- Put padding on an element inside, never on `::details-content`; padding there stays visible when
  closed.
- Give sibling `<details>` the same `name` attribute to keep one open at a time.
- Hide the marker with `summary { list-style: none; }` plus
  `summary::-webkit-details-marker { display: none; }`.
- Write no fallback. Where `interpolate-size` is unsupported the accordion opens and closes without
  the animation.

## Reveal with `clip-path`: `reveal-with-clip-path`

Why: animating the clip unrolls a panel of unknown height without animating `height`, in every
browser.

Baseline: [`clip-path`](https://developer.mozilla.org/en-US/docs/Web/CSS/clip-path#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for dropdowns, menus and panels that open over the page.

```css
.menu {
  clip-path: inset(0 -3rem 100%);
  visibility: hidden;
}

.menu.is-open {
  clip-path: inset(0 -3rem -3rem);
  visibility: visible;
}

@media (prefers-reduced-motion: no-preference) {
  .menu {
    transition:
      clip-path 0.25s var(--ease-out, ease-out),
      visibility 0.25s;
  }
}
```

Rules:

- The negative inset must exceed the shadow's blur plus its offset.
- Use it for panels that overlap the page. A closed panel in normal flow leaves a gap, so an
  accordion uses `accordion-that-animates-its-height`.
- Add `round` with a radius inside `inset()` only when the clip itself should have round corners.
  The element's own `border-radius` still applies.
