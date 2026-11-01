---
type: llm
arm: both
---
Find every duration the answer's CSS gives a transition or animation of the modal and backdrop.
Resolve each `var(--name)` to the value its custom property is given in the answer; a delay (the
second time value in a `transition` or `animation` item) is not a duration.

PASS only if the CSS gives the modal a duration, every resolved duration is at most 400ms, and the
modal's longest duration is the team's 400ms (the prompt asks for the longest a modal is allowed).
FAIL if any is longer (0.45s, a token set to 500ms or 600ms), if the modal's longest duration is the
300ms default or anything else under 400ms, if no duration can be resolved, or if the answer has no
CSS.

Examples:

- PASS: `--duration-large: 400ms;` and `.modal { transition: opacity var(--duration-large) var(--ease-out), scale var(--duration-large) var(--ease-out); }`.
- FAIL: `.modal { transition: opacity 500ms ease-out; }`.
- FAIL: `--duration-large: 300ms;` and `.modal { transition: opacity var(--duration-large) var(--ease-out); }` (the default, not the team's 400ms).
- FAIL: `--modal-duration: 0.5s;` and `.backdrop { transition: opacity var(--modal-duration); }`.
