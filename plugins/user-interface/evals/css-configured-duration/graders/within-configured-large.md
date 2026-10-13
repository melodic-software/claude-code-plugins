---
type: llm
arm: both
---
Find every duration the answer's CSS gives a transition or animation of the modal and backdrop.
Resolve each `var(--name)` to the value its custom property is given in the answer; a delay (the
second time value in a `transition` or `animation` item) is not a duration.

PASS only if the CSS gives the modal a duration and every resolved duration is at most 400ms.
FAIL if any is longer (the 500ms default, 0.45s, a token set to 600ms), if no duration can be
resolved, or if the answer has no CSS.

Examples:

- PASS: `--duration-large: 400ms;` and `.modal { transition: opacity var(--duration-large) var(--ease-out), scale var(--duration-large) var(--ease-out); }`.
- FAIL: `.modal { transition: opacity 500ms ease-out; }`.
- FAIL: `--modal-duration: 0.5s;` and `.backdrop { transition: opacity var(--modal-duration); }`.
