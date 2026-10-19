---
type: llm
arm: both
---
PASS only if the reply shapes the button's corners with `border-radius`, optionally with
`corner-shape` as an enhancement, and the button keeps a visible focus indicator (a `:focus-visible`
outline or equivalent) that no `clip-path` on the button cuts off. FAIL if the reply puts a
`clip-path` on the focusable button, leaves the button with no visible focus, or contains no CSS.
