---
type: llm
arm: both
---
PASS only if the reply's CSS has at least one transition or animation and none of them uses an
ease-in curve. Passing curves: `ease-out`, `ease-in-out`, `ease`, `linear`, no timing function
(which means `ease`), a custom property named for one of those, or a `cubic-bezier()` that ends
slow, either an ease-out shape such as `cubic-bezier(0.23, 1, 0.32, 1)` or an ease-in-out shape
such as `cubic-bezier(0.77, 0, 0.175, 1)`. FAIL if any uses `ease-in`, a custom property named for
it, or a `cubic-bezier()` that starts slow and ends fast such as `cubic-bezier(0.55, 0, 1, 0.45)`,
or if the reply contains no transition or animation.
