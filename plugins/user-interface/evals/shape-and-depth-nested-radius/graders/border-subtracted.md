---
type: llm
arm: both
---
PASS only if the radius the reply recommends for the preview pane equals the panel's 28px outer
radius minus the 2px border minus the 10px padding: 16px, in any form that computes to it (`16px`,
`1rem` at a 16px root, `rounded-[16px]`, `calc(28px - 10px - 2px)` in any order, a `max(0px, ...)`
or custom property expression that subtracts the border width and the padding from the outer radius,
or an inner-radius token of 16px with the panel's 28px derived from it by adding the border and the
padding). FAIL if the recommended radius is 28px, 18px, 26px or any other value, if it subtracts
only the padding or only the border, if the reply mentions 16px but recommends a different value, or
if the reply recommends no radius.
