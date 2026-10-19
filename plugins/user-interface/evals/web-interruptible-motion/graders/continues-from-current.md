---
type: llm
arm: both
---
PASS only if the reply animates the panel so that a reversal mid-animation continues from the current
value and velocity: a spring (a spring library, or a spring-driven value that is retargeted) or a CSS
`transition` on a property that the open and closed states set, so the browser retargets from the
current value. FAIL if the open and close motion is a `@keyframes` animation that is re-applied or
restarted on each toggle (so a reversal jumps back to the first keyframe, that is, restarts from
zero), or if the reply contains no animation code.
