---
type: llm
arm: both
---
PASS only if the reply's CSS for `data-state="closing"` makes the dismissed toast fade and move a
small distance toward the bottom or right edge, the exit's duration is shorter than the toast's
entrance and fits the app's 300ms removal, and the exit eases on an accelerating curve: a custom
`cubic-bezier()` that starts slow and ends fast (its first control point's y at or near 0 and its x
above 0, and its second control point's y no greater than its x, such as
`cubic-bezier(0.3, 0, 1, 1)` or `cubic-bezier(0.4, 0, 1, 1)`) or a token the reply defines that
way. FAIL if the exit runs as long as the entrance or longer, if it runs past 300ms, if it slides
the toast the full viewport height or off-screen by its own height several times over, if it
disappears with no transition, if it eases out on a decelerating curve, if it uses an ease-in-out
shape that settles slowly at the end (`ease-in-out`, `cubic-bezier(0.77, 0, 0.175, 1)`), if it
uses the bare `ease-in` keyword, or if the reply contains no CSS.
