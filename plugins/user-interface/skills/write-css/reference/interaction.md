# Interaction

The project's design system, tokens and conventions override everything in this file. Literal
values in the examples are this skill's defaults: use one only where the project has no token for
it, and name each default you used.

Each `Baseline:` line links the live compat entry; never copy version numbers from it. As of
2026-10-11; recheck when that entry's Baseline status changes or the project's browser target moves.

Contents: `one-focus-ring-with-focus-visible`, `hover-styles-only-where-hover-exists`,
`press-feedback`, `hit-area-larger-than-the-visual`, `whole-card-clickable-from-one-link`,
`has-for-parent-and-page-state`, `form-feedback-with-user-invalid`,
`textarea-that-grows-with-its-content`.

## One focus ring with `:focus-visible`: `one-focus-ring-with-focus-visible`

Why: keyboard users get a visible ring and mouse users do not, with one rule and no
`outline: none`.

Baseline: [`:focus-visible`](https://developer.mozilla.org/en-US/docs/Web/CSS/:focus-visible#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it as the focus style for every interactive element. Never write `outline: none`.

```css
:focus-visible {
  outline: max(2px, 0.08em) solid currentColor;
  outline-offset: 0.25em;
}
```

Rules:

- On a filled button `currentColor` can fail contrast. Use the button's background color there.
- A component that draws its ring with `box-shadow` keeps `outline-color: transparent`, never
  `outline: none`, so forced-colors mode can repaint it.

## Hover styles only where hover exists: `hover-styles-only-where-hover-exists`

Why: a tap on a touch screen otherwise leaves the hover state stuck.

Baseline: [`hover` media feature](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/hover#browser_compatibility),
[`pointer`](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/pointer#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on every `:hover` rule.

```css
@media (hover: hover) and (pointer: fine) {
  .button:hover { background: var(--primary-hover); }
}
```

Rules:

- A framework's hover variant may wrap itself in `(hover: hover)` only. Check its compiled output;
  write the full query by hand wherever it is missing.
- Touch users still need feedback on press. Give it with `:active`, which works for every input.

## Press feedback: `press-feedback`

Why: a pressed control that visibly reacts confirms the press, on every input type.

Baseline: [`:active`](https://developer.mozilla.org/en-US/docs/Web/CSS/:active#browser_compatibility),
widely available. As of 2026-10-11, recheck on a status change.

Use it on every button and anything else that can be pressed.

```css
.button:active { transform: scale(0.97); }

@media (prefers-reduced-motion: no-preference) {
  .button { transition: transform 160ms var(--ease-out, ease-out); }
}
```

Rules:

- Keep the scale between 0.95 and 0.98.
- `the-reset` (`foundations.md`) removes the tap highlight; without this a tap gives no feedback.
- When feedback needs a script, listen for `pointerdown`, not `click`.

## Hit area larger than the visual: `hit-area-larger-than-the-visual`

Why: a pseudo-element grows the target to at least 44px without changing what the user sees.

Baseline: [`inset`](https://developer.mozilla.org/en-US/docs/Web/CSS/inset#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it on icon buttons, close buttons and any target that looks smaller than 44px.

```css
.icon-button { position: relative; }

.icon-button::after {
  content: "";
  position: absolute;
  inset: min(0px, (100% - 44px) / 2);
}
```

Rules:

- `overflow: hidden` or `clip` on the button cuts the area off.
- It does not work on `<input>`, which has no pseudo-elements. Wrap it in a `<label>`.

## Whole card clickable from one link: `whole-card-clickable-from-one-link`

Why: one real link stretched over the card keeps link text short for screen readers and needs no
click handler on a `div`.

Baseline: [`:has()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:has#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for cards, list rows and tiles where the whole area navigates, in place of an `<a>` wrapped
around the card.

```html
<article class="card">
  <h3><a class="card-link" href="/reports/q3">Quarterly report</a></h3>
  <p>Revenue grew in every region.</p>
  <button type="button">Save</button>
</article>
```

```css
.card { position: relative; }

.card-link::after {
  content: "";
  position: absolute;
  inset: 0;
}

.card-link:focus-visible { outline: 2px solid transparent; }

.card:has(.card-link:focus-visible) {
  outline: 2px solid currentColor;
  outline-offset: 2px;
}

.card :is(button, a:not(.card-link)) {
  position: relative;
  z-index: 1;
}
```

Rules:

- No element between the card and the link may be positioned; the overlay would size itself to
  that element.
- The link's own ring is made transparent, never removed (`one-focus-ring-with-focus-visible`).
  Write the full `2px solid transparent`, so no engine's default outline style shows through.
- Text under the overlay cannot be selected. Accept it.
- Put hover styles on `.card:hover`, inside the query from `hover-styles-only-where-hover-exists`.

## `:has()` for parent and page state: `has-for-parent-and-page-state`

Why: the parent styles itself from what it contains, replacing a script that toggles a class on
it.

Baseline: [`:has()`](https://developer.mozilla.org/en-US/docs/Web/CSS/:has#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it wherever a script adds a class to a parent because of its contents or a child's state.

```css
article:has(img) { grid-column: span 2; }
h2:has(+ p) { margin-block-end: 0; }
form:has(:focus-visible) { background: var(--surface-raised); }

html { scrollbar-gutter: stable; }
html:has(dialog:modal) { overflow: hidden; }
```

Rules:

- `:modal` matches `showModal()` only, so a non-modal dialog does not lock the page.
- Keep `scrollbar-gutter: stable` with the scroll lock, or the page shifts sideways when the
  scrollbar disappears. `the-reset` (`foundations.md`) sets it.
- `:has()` cannot be nested inside `:has()`.

## Form feedback with `:user-invalid`: `form-feedback-with-user-invalid`

Why: the browser waits until the user has interacted before flagging a field, replacing blur
listeners and a "touched" class.

Baseline: [`:user-invalid`](https://developer.mozilla.org/en-US/docs/Web/CSS/:user-invalid#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for inline form validation.

```css
input:user-invalid { border-color: var(--danger); }
input:user-valid { border-color: var(--success); }
```

```html
<input type="password" required minlength="8">
```

Rules:

- Color alone is not enough feedback. Pair it with text or an icon.
- The server still validates.

## Textarea that grows with its content: `textarea-that-grows-with-its-content`

Why: `field-sizing: content` sizes the textarea to its text, with no auto-grow script and no
hidden mirror element.

Baseline: [`field-sizing`](https://developer.mozilla.org/en-US/docs/Web/CSS/field-sizing#browser_compatibility).
As of 2026-10-11, recheck on a status change.

Use it for any multi-line input, such as a chat composer or a comment box.

```css
textarea {
  field-sizing: content;
  min-block-size: 3lh;
  max-block-size: 12lh;
  resize: none;
}
```

The height snaps to each new line. To animate it, wrap the textarea and let a `ResizeObserver`
copy its height onto the wrapper, which transitions.

```html
<div class="field"><textarea></textarea></div>
```

```css
.field {
  box-sizing: content-box;
  overflow: clip;
}

@media (prefers-reduced-motion: no-preference) {
  .field { transition: height 0.2s var(--ease-out, ease-out); }
}
```

```js
const textarea = document.querySelector(".field textarea");

new ResizeObserver(([entry]) => {
  textarea.parentElement.style.height = `${entry.borderBoxSize[0].blockSize}px`;
}).observe(textarea);
```

Rules:

- Bound it with a minimum and maximum size. A fixed height brings the fixed size back. Past the
  maximum the textarea scrolls.
- Put the border and background on the wrapper and leave the textarea bare: the box the user sees
  must be the one that animates.
- Keep the wrapper `content-box`. The observer writes the textarea's full height, and a
  `border-box` wrapper would subtract its own border.
- Write no fallback. Without `field-sizing` the textarea stays fixed and scrolls.
