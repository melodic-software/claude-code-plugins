---
type: llm
arm: both
---
Expectations: "The answer says a clip has a hard edge and a mask can have soft or gradient
edges" and "The answer names the before and after slider, or says either can drive a before and
after reveal".

PASS only if the reply says a clip cuts to a shape with a hard edge while a mask can have soft or
gradient edges, and names the before and after slider (the draggable divider) or says either can
drive the reveal. FAIL if it treats them as the same, swaps the edge behavior, or says nothing about
the before and after reveal.
