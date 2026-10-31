# Show and hide

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

The motion rules these recipes serve (origin, paired timing, durations, reduced motion) are the
`motion` concern of `/user-interface:design`; the recipes are the CSS for them.

Contents: `enter-and-exit-transitions-from-display-none`, `popover-anchored-to-its-trigger`,
`popover-that-scales-from-its-trigger`, `popover-inside-a-modal`,
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
dialog::backdrop,
[popover] {
  opacity: 0;
  transition-property: opacity, display, overlay;
  transition-behavior: allow-discrete;
  transition-duration: 0.16s;
  transition-timing-function: var(--ease-out, ease-out);
}

dialog,
dialog::backdrop { transition-timing-function: var(--ease-in, cubic-bezier(0.3, 0, 1, 1)); }

dialog[open],
dialog[open]::backdrop {
  opacity: 1;
  transition-duration: 0.2s;
  transition-timing-function: var(--ease-out, ease-out);
}

[popover]:popover-open {
  opacity: 1;
  transition-duration: 0.2s;
}

@starting-style {
  dialog[open],
  [popover]:popover-open,
  dialog[open]::backdrop { opacity: 0; }
}

@media (prefers-reduced-motion: no-preference) {
  dialog,
  [popover] {
    translate: 0 0.5rem;
    transition-property: opacity, translate, display, overlay;
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
  fades. Give it the dialog's duration and easing: they move as one unit.
- A transition runs on the timing of the state it moves to, so the closed rules carry the exit and
  the open rules the entrance. Closing a dialog is a permanent exit (the `motion` concern): it runs
  shorter on the `in` curve. A popover is toggled by its trigger: it closes shorter on `out`. The
  `var()` fallback is the `in` default, never the bare `ease-in` keyword.
- A dialog may scale in instead of rising: it starts at a scale between `0.95` and `0.97` with
  `opacity: 0` and ends at `scale(1)`, inside the same motion query, and it stays centered. The
  exit is the same but faster.
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

## Popover that scales from its trigger: `popover-that-scales-from-its-trigger`

Why: a menu that grows out of the button that opened it stays connected to it; one that grows from
its own center floats detached.

Baseline: [`transform-origin`](https://developer.mozilla.org/en-US/docs/Web/CSS/transform-origin#browser_compatibility),
widely available. As of 2026-10-29, recheck on a status change.

Use it for dropdowns, menus, popovers and tooltips that scale in. The origin rule is the `motion`
concern's; many component libraries expose the trigger side as a CSS variable (pointer below).

```css
.popover {
  transform-origin: var(--radix-popper-transform-origin, var(--transform-origin, top));
}

.dropdown {
  transform-origin: var(--radix-dropdown-menu-content-transform-origin);
  /* Base UI: var(--transform-origin) */
  opacity: 0;
}

.dropdown[data-open] { opacity: 1; }

@media (prefers-reduced-motion: no-preference) {
  .dropdown {
    transform: scale(0.95);
    transition:
      opacity 120ms var(--ease-out, ease-out),
      transform 120ms var(--ease-out, ease-out);
  }

  .dropdown[data-open] {
    transform: scale(1);
    transition-duration: 150ms;
  }
}
```

A tooltip is the same, faster and subtler. While one tooltip in a group is open its neighbors open
with no animation (the `motion` concern's instant group); `data-instant` below is that state:

```css
.tooltip {
  transform-origin: var(--transform-origin);
  transition: opacity 125ms var(--ease-out, ease-out);
}

.tooltip[data-starting-style],
.tooltip[data-ending-style] { opacity: 0; }

.tooltip[data-ending-style] { transition-duration: 100ms; }

.tooltip[data-instant] { transition-duration: 0ms; }

@media (prefers-reduced-motion: no-preference) {
  .tooltip {
    transition:
      transform 125ms var(--ease-out, ease-out),
      opacity 125ms var(--ease-out, ease-out);
  }

  .tooltip[data-starting-style],
  .tooltip[data-ending-style] { transform: scale(0.97); }
}
```

Rules:

- Use the variable the project's library exposes, so the origin follows a flip to the other side
  of the trigger. With no library variable, set a fixed origin on the trigger's side, such as
  `top left` for a menu that opens below the start edge, and mirror it under `:dir(rtl)`.
- The variable names and state attributes are library API and differ per library and per
  component: the selectors above illustrate two libraries. Match them to the library in use from
  its docs (pointer below).

- **Pointer**: Radix Primitives, "Dropdown Menu", API reference `Content`,
  <https://www.radix-ui.com/primitives/docs/components/dropdown-menu#content>; "Tooltip", API
  reference `Content`, <https://www.radix-ui.com/primitives/docs/components/tooltip#content>; Base
  UI, "Popover", API reference `Positioner` and `Popup`,
  <https://base-ui.com/react/components/popover#positioner>,
  <https://base-ui.com/react/components/popover#popup>.
- **As of**: 2026-10-29.
- **Recheck trigger**: either library renames its origin variable or its starting, ending or
  instant state.

## Popover inside a modal: `popover-inside-a-modal`

Why: a select inside a dialog should close on an outside click without closing the dialog too.

When you open a popover inside a modal (think a custom select), clicking outside the popover to
close it also closes the modal. The desired behavior is to close the select on click outside while
keeping the modal open. This often happens because custom dropdowns or select components are
rendered in a portal. The modal then treats the interaction as an outside click because,
technically, the dropdown isn't inside the modal in the DOM, it's rendered elsewhere via a portal.

Rules:

- Fix it where the modal decides what counts as outside: a press inside the open popover's portal
  is inside the modal. The first outside click closes only the popover; a click on the backdrop
  with no popover open closes the modal.
- Primitives from one library usually coordinate this already. Mixing a modal from one library
  with a select from another, or a hand-rolled outside-click handler, is where it breaks; look up
  how the project's library registers a nested layer before writing a handler of your own.
- Check it by hand: open the select, click the dialog body beside it, and confirm the dialog stays
  open with its value unchanged.

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
      height 0.25s var(--ease-out, ease-out),
      content-visibility 0.25s allow-discrete;
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
