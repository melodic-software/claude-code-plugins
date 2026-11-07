---
type: llm
arm: both
---
Expectation: "The answer reads or cites touch-web.md or applies at least three of its rules
(hover gating, target size, input keyboard, no zoom lock, viewport units)".

PASS only if the design applies at least three of these to the signup form: hover effects gated to
hover-capable pointers (press feedback that does not depend on hover), touch targets that meet the
WCAG target size criterion, the right on-screen keyboard per field (`type`, `inputmode` or
`autocomplete`), no zoom lock, and safe viewport sizing (`dvh`/`svh` or equivalent rather than
`100vh`). FAIL if it applies fewer than three, or designs only for desktop.
