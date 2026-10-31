---
type: llm
arm: both
---
PASS only if the reply's light-theme card gets its depth from a `box-shadow` (directly or through a
custom property) made of two or more comma-separated shadow layers, and the solid `1px solid #e0e0e0`
depth border is removed or replaced (a 1px spread ring inside the shadow stack counts as its
replacement). FAIL if the card keeps the solid border as its depth cue, uses a single shadow layer,
or the reply contains no CSS.
