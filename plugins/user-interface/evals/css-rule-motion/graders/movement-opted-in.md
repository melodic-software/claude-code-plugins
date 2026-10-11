---
type: llm
arm: both
---
PASS only if every transition or animation in the reply that changes `transform`, `translate`,
`scale` or `rotate` is declared inside `@media (prefers-reduced-motion: no-preference)`, and the reply
does not rely on a global `prefers-reduced-motion: reduce` rule that sets durations to near zero.
Opacity and color transitions may sit outside the query. FAIL if a movement transition is declared
outside the no-preference query, or the reply contains no CSS.
