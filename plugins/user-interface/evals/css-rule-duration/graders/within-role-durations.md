---
type: llm
arm: both
---
Find every duration the answer's CSS gives a transition or animation. Resolve each `var(--name)` to
the value its custom property is given in the answer; a delay (the second time value in a
`transition` or `animation` item) is not a duration.

PASS only if the CSS gives each element a duration, the dropdown's are at most 250ms and the
tooltip's at most 200ms. FAIL if any resolved duration is longer (600ms, 0.3s, a token set to
350ms), if no duration can be resolved, or if the answer has no CSS.

Examples:

- PASS: `--duration-medium: 250ms;` and `.dropdown { transition: opacity var(--duration-medium) var(--ease-out); }`, with the tooltip at 150ms.
- PASS: `.tooltip { transition: opacity 150ms ease-out 500ms; }` (500ms is the delay).
- FAIL: `--lux-fade: 600ms;` and `.dropdown { transition: opacity var(--lux-fade) ease; }`.
- FAIL: `.tooltip { animation: fade .3s ease-out; }`.
