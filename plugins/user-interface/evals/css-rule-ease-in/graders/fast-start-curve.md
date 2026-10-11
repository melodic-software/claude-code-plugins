---
type: llm
arm: both
---
PASS only if every transition or animation in the reply's CSS uses a curve that starts fast:
`ease-out`, `ease-in-out`, a custom property named for one of those, or a `cubic-bezier()` whose
first control point rises faster than it advances (for example `cubic-bezier(0.23, 1, 0.32, 1)`).
FAIL if any uses `ease-in` or a slow-start `cubic-bezier()` such as `cubic-bezier(0.55, 0, 1, 0.45)`,
or if the reply contains no transition or animation.
