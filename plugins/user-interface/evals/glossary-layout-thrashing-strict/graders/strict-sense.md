---
type: llm
arm: both
---
Expectations: "The answer says animating height every frame is not layout thrashing in the
strict sense", "The answer defines layout thrashing as repeated forced synchronous layout from
script reads that follow style writes", "The answer calls the height animation a layout-triggering
animation or says it re-runs layout every frame" and "The answer does not agree that the
teammate's use of the term is correct".

PASS only if the reply says the height animation is not layout thrashing in the strict sense,
defines layout thrashing as repeated forced synchronous layout from script reads after style
writes, and calls the height animation a layout-triggering animation (it re-runs layout every
frame). FAIL if it agrees with the teammate, or never gives the strict definition.
