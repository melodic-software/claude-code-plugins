---
type: llm
arm: both
---
PASS only if, for at least one feature the browser target does not support (anchor positioning,
the popover attribute, `@starting-style`, `transition-behavior: allow-discrete`), the answer either
wraps it in `@supports` or states that it skipped or replaced it, naming both the feature and the
target browser or browserslist. FAIL if every such feature is used unconditionally with no stated
skip, or a skip names neither the feature nor the target.

Examples:
- PASS: `@supports (anchor-name: --tip) { #tip { position-anchor: --tip; } }`
- PASS: "Safari 15.4 lacks support for anchor positioning, so I positioned the tooltip absolutely."
- PASS: "Your browserslist target includes Safari 15, which does not support anchor positioning."
- FAIL: "I skipped a few newer features."
- FAIL: `#tip { position-anchor: --tip; top: anchor(bottom); }` with no `@supports` and no note.
