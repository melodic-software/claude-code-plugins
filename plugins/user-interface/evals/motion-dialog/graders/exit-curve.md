---
type: llm
arm: both
---
Closing the confirm dialog is a permanent exit. A CSS transition runs on the timing function of the
state it moves to, so the close takes the curve that applies without `[open]` and the open the
curve that applies with it; one transition that applies in both states gives both directions the
same curve. PASS only if the dialog's close runs on an accelerate curve
and its open does not: a `cubic-bezier()` whose first control point's y is at or near 0 with its x
above 0 and whose second control point's y is no greater than its x, such as
`cubic-bezier(0.3, 0, 1, 1)`, or a custom property the reply defines, or gives as a fallback, with
such a curve. FAIL if the close runs on the bare `ease-in` keyword, on `ease-out` or another curve
that does not accelerate (one transition shared by open and close on a decelerating curve
included), on an ease-in-out shape such as `cubic-bezier(0.77, 0, 0.175, 1)`, if the open also
accelerates, or if the reply contains no CSS.
