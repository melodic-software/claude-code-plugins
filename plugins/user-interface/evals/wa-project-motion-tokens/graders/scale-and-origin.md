---
type: llm
arm: both
---
Expectations: "The entrance starts from a scale between 0.9 and 0.98 with zero opacity,
never scale(0)" and "The transform origin is set toward the trigger, not the center".

PASS only if the dropdown enters from a scale between 0.9 and 0.98 with opacity 0, never
`scale(0)`, and its `transform-origin` is set toward the trigger (the edge or corner where it meets
the button). FAIL if it scales from 0 or under 0.9, has no origin or a centered one, or has no CSS.
