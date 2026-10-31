---
type: llm
arm: both
---
The prompt explicitly asks for an exit that accelerates away, and a dismissed toast is a permanent
exit. PASS only if the reply's CSS gives the dismissal a transition or animation on an accelerate
curve and the reply warns that its slow start can read as lag. An accelerate curve is a
`cubic-bezier()` that starts slow and ends fast: its first control point's y is at or near 0 with
its x above 0, and its second control point's y is no greater than its x, such as
`cubic-bezier(0.3, 0, 1, 1)`, `cubic-bezier(0.4, 0, 1, 1)` or `cubic-bezier(0.55, 0, 1, 0.45)`. A
custom property counts when the reply defines it, or gives it as a fallback, with such a curve.
FAIL if the exit uses the bare `ease-in` keyword (even with the warning), if it uses a curve that
does not accelerate (`ease-out`, `ease-in-out`, `ease`, `linear`, no timing function, or a `cubic-bezier()`
whose second control point sits above the diagonal, such as `cubic-bezier(0.77, 0, 0.175, 1)`), if
the reply names no lag or slow-start trade-off, or if the reply contains no transition or animation.
