---
type: llm
arm: both
---
PASS only if the reply contains CSS and every `:hover` selector in it sits inside an
`@media` block whose condition includes `(hover: hover)` (with or without `(pointer: fine)`).
FAIL if any `:hover` rule is written outside such a block, or if the reply contains no CSS.
