---
type: llm
arm: both
---
Expectation: "The answer uses the drawer easing curve and a duration within the large limit
for opening and closing the sheet".

PASS only if the sheet opens and closes on the drawer curve (`cubic-bezier(0.32, 0.72, 0, 1)`, or
the resolved drawer curve named as such) with durations of at most 300ms, the default `large`
role. FAIL if a duration is longer, or the curve is another one with no reason given.
