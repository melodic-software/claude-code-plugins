---
bump: patch
---

### Fixed

- The `security-review-kill-switch-fail-open` eval case now requires the fail-open finding at
  IMPORTANT with `critical-findings: 0`, the kill-switch cap `/review:security-review` states, not
  CRITICAL.
