# Interaction terms

How elements respond to input. Each entry gives the term, a definition, and the line between it and
the term most often confused with it.

## Interaction: `interaction`

### Affordance: `affordance`

The visual signal that tells you how something can be used. A button looks pressable. A link looks
clickable. When affordance is missing, users guess.

**Versus:** a signifier is the visible cue itself; affordance is what the element can be used for,
as the cue tells it.

### Focus state: `focus-state`

The visible indicator that an element is keyboard-focused. Removing it is an accessibility failure.
Replace it with a custom style, never just delete it.

**Versus:** hover state follows the pointer; focus state follows the keyboard.

### Disabled state: `disabled-state`

A non-interactive element. Using opacity alone is unreliable since it can pass or fail contrast
checks unpredictably depending on the background. A specific muted token is more predictable.

**Versus:** a read-only field is still focusable and selectable; a disabled one is not interactive
at all.

### Pointer events: `pointer-events`

Whether an element can receive mouse or touch input. Setting to `none` makes an element visually
present but non-interactive, useful for decorative layers that should not intercept clicks.

**Versus:** the pointer events input model in `engineering.md` is one event API for mouse, touch and
pen; this is the CSS property that switches input on or off for an element.

### Debounce: `debounce`

A delay before firing a function, reset each time it is triggered. Stops a search input making a
request on every keystroke. 300ms is a common threshold.

Engineering: wait until the events stop (typing, resizing) before running the handler, so it fires
once at the end instead of on every event.

**Versus:** throttle runs the handler at most once per interval while events keep firing; debounce
waits until they stop.

### Copy to clipboard: `copy-to-clipboard`

A button that copies text. Needs visible confirmation, typically a checkmark for a second or two.
Without it, users click it repeatedly thinking it failed.

**Versus:** a success message confirms a completed action in words; copy to clipboard needs its own
brief in-place confirmation.

### Hover state: `hover-state`

The visual change when a cursor moves over an interactive element. Should confirm interactivity
through cursor change, color shift, or both. Color alone is not enough.

**Versus:** active state is the change while pressed; hover state is the change while the pointer is
over the element.

### Active state: `active-state`

The visual change when an element is pressed. Without it, buttons feel unresponsive. A small scale
or color shift is enough.

**Versus:** hover state shows before the press; active state shows during it. Press / tap feedback
in `motion.md` is the motion that carries it.

### Cursor: `cursor`

The pointer icon that signals what an element does. Pointer means clickable. Default means static.
Text means selectable. The wrong cursor breaks the implicit contract.

**Versus:** hover state is the element's visual change; the cursor is the pointer icon itself.

### Optimistic update: `optimistic-update`

Updating the UI before the server confirms the action. Feels instant. Requires a rollback if the
request fails.

**Versus:** a pessimistic update waits for the server and shows a pending state; an optimistic one
shows the result first and rolls back on failure.

### Touch target: `touch-target`

The tappable area of an interactive element. Standards set a minimum size for it. The visual
element can be smaller than the touch target.

**Versus:** the visual element is what the eye sees; the touch target is the area that responds,
which can be larger. Hit area in `engineering.md` is the same idea in engineering terms.

### Skip link: `skip-link`

A visually hidden link that jumps to the main content. Appears on focus for keyboard users. Without
it, every page requires tabbing through the full navigation first.

**Versus:** a focus trap keeps focus inside an overlay; a skip link moves focus past repeated
navigation.

## Sources

Touch target names a minimum size without stating it; standards set more than one.

- **Pointer**: when a target size decides a finding, fetch https://www.w3.org/TR/WCAG22/#target-size-minimum and https://www.w3.org/TR/WCAG22/#target-size-enhanced live.
- **As of**: 2026-10-28
- **Recheck trigger**: a WCAG version after 2.2 becomes a W3C Recommendation.
