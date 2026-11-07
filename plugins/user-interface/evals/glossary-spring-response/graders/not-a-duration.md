---
type: llm
arm: both
---
Expectations: "The answer defines response as how quickly the spring tries to reach its
target", "The answer calls response the designer-facing spring parameter, as against raw
stiffness", "The answer does not say flatly that response is the same as a duration" and "The
answer says the response maps to a different parameter per platform and points at the platform
docs".

PASS only if the reply defines response as how quickly the spring tries to reach its target, calls
it the designer-facing parameter as against raw stiffness, does not say flatly that it is a
duration, and says each platform maps it to a different parameter, pointing at the platform's docs.
FAIL if it answers yes, response is the duration, or misses the per-platform mapping.
