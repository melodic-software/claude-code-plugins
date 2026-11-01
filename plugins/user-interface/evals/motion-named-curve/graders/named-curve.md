---
type: llm
arm: both
---
PASS only if the pulse's timing function is a `cubic-bezier()` that the reply names as a curve from
an established easing collection (for example "easeInOutSine" from easings.net or Robert Penner's
equations, `cubic-bezier(0.37, 0, 0.63, 1)` or `cubic-bezier(0.445, 0.05, 0.55, 0.95)`, or a named
in-out family such as quad or cubic from the plugin's easing library), and the reply presents it as a
default or starting point the user can tune. FAIL if the reply writes `cubic-bezier()` control
points it attributes to no named curve or collection, if it uses a CSS keyword (`ease-in-out`,
`ease`, `linear`) instead of a curve, if it gives the curve no word as a default to tune, if the
pulse has no timing function, or if the reply contains no CSS.
