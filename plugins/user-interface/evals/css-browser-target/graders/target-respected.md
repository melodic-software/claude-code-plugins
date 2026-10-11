---
type: llm
arm: both
---
PASS only if the answer takes the target from .browserslistrc, and for each feature it uses that
the target does not fully support (CSS anchor positioning, the popover attribute, transitions from
`display: none` such as `@starting-style` or `transition-behavior: allow-discrete`) it either wraps
the feature in `@supports` with a fallback that still positions and shows the tooltip, or leaves it
out and states the reason. FAIL if it uses any of those features unconditionally with no fallback,
or never mentions the browser target.
