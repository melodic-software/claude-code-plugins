---
type: llm
arm: both
---
PASS only if the container's `border-radius` equals the inner token plus the padding,
`calc(var(--radius-control) + 16px)` or 22px, and the input and button keep
`var(--radius-control)`. FAIL if the button's or input's radius changes or is derived from the
container's (for example `max(0px, var(--outer) - 16px)`, which reaches zero here), if the container
takes any other radius (6px, 16px, a pill), or if the reply contains no CSS.
