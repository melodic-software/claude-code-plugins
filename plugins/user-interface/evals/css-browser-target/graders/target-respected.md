---
type: llm
arm: both
---
PASS only if the answer takes the target from .browserslistrc, and for each feature it uses that
the target does not fully support (CSS anchor positioning, the popover attribute, transitions from
`display: none` such as `@starting-style` or `transition-behavior: allow-discrete`) it either wraps
the feature in `@supports`, or says how the tooltip behaves below the target (for example that it
appears without the transition, or unanchored), or leaves the feature out and states the reason.
FAIL if it uses any of those features outside `@supports` without saying how the tooltip behaves
below the target, or never mentions the browser target.
