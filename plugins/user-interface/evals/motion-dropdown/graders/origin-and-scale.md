---
type: llm
arm: both
---
PASS only if the reply's CSS makes the menu enter from a scale between 0.9 and 0.97 together with
opacity 0, settling at scale 1 and opacity 1, and sets the menu's `transform-origin` toward the
trigger: the top-left corner or top edge where the menu meets the button (`top left`, `left top`,
`top`, `0 0`), or a variable a component library exposes for the trigger side. The prompt uses no
component library, so a fixed origin at the trigger is right. A small upward or downward nudge
alongside the scale also passes. FAIL if the menu starts from `scale(0)`, `scale: 0` or any scale
under 0.9, if it scales with no `transform-origin` or with `transform-origin: center` (it grows
from its own center), if it only fades or only slides with no scale at all while the reply claims
to scale, if the origin appears only in prose, or if the reply contains no CSS.
