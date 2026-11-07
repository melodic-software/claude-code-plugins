---
type: llm
arm: both
---
Expectations: "Dismissal triggers on a fast release (velocity) as well as on distance" and
"The sheet settles with a spring that receives the release velocity".

PASS only if the sheet dismisses on a fast release (a velocity threshold) as well as past a drag
distance, and settles (closing or snapping back) with a spring given the release velocity. FAIL if
dismissal depends on distance alone, or the settle ignores the release velocity.
