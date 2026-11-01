---
type: llm
arm: both
---
PASS only if each icon control's tappable area is at least 24 by 24 CSS pixels (through its own
width and height, `min-inline-size` and `min-block-size`, padding, or a pseudo-element that extends
the hit area), the 20px icon may keep its visual size, and the extended hit areas of neighbors do
not overlap (the gap grows, or a pseudo-element extends no further than half the gap). FAIL if any
control's hit area stays under 24px in either dimension, if a pseudo-element extends the hit area
past half the 4px gap without the gap growing so neighbors overlap, or if the reply contains no CSS.
