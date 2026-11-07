---
type: llm
arm: both
---
Expectations: "The panel leaves through the right edge it entered from" and "No duration
exceeds the configured large role (300ms at the defaults)".

PASS only if the panel enters from the right and leaves back through the right edge, and no
duration in the answer exceeds 300ms. FAIL if it exits another way (fades in place, drops down,
leaves left) or any duration exceeds 300ms.
