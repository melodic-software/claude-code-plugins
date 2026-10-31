---
type: llm
arm: both
---
PASS only if the reply's code takes the closed drawer's links out of the tab order: the closed panel
gets the `inert` attribute, `visibility: hidden` (with or without a delayed transition so the exit
still animates), `display: none`, the `hidden` attribute, or is not rendered while closed. FAIL if
the closed panel is hidden only by `opacity: 0`, a `transform` that moves it off-screen, or both, as
in the prompt; if it is hidden only with `aria-hidden="true"` or `pointer-events: none`, which leave
its links in the tab order; if the fix appears only in prose; or if the reply contains no code.
