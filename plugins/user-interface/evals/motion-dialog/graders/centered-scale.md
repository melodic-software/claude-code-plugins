---
type: llm
arm: both
---
PASS only if the reply's CSS opens the dialog with a fade combined with a scale that starts between
0.9 and 0.97 and ends at 1, keeps the dialog centered (no `transform-origin` toward a corner or
trigger), and puts that scale inside `@media (prefers-reduced-motion: no-preference)` or removes it
under `@media (prefers-reduced-motion: reduce)`, so under reduced motion the fade stays and only the
scale goes. FAIL if
the dialog starts from `scale(0)` or below 0.9, if it slides in from off-screen (a translate of the
viewport or of its own height), if it bounces or overshoots (a spring with bounce, a keyframe past
scale 1, a back-out curve), if the scale still plays under reduced motion, if the reduced-motion
rule removes the fade too (`animation: none` and `transition: none` on everything), or if the reply
contains no CSS.
