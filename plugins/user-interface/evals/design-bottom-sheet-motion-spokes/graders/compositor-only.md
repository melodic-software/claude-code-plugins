---
type: llm
arm: both
---
Expectations: "The answer animates only transform and opacity, or says layout properties
cause the dropped frames" and "The answer covers all three parts the request names (opening, swipe
to dismiss and dropped frames) in this pass rather than leaving one for a later pass".

PASS only if the sheet animates only `transform` and `opacity` (or the answer says animating layout
properties such as `height`, `top` or `bottom` causes the dropped frames), and the answer covers
opening, swipe to dismiss and the dropped frames in this answer. FAIL if it animates a layout
property, or leaves one of the three parts for a later pass.
