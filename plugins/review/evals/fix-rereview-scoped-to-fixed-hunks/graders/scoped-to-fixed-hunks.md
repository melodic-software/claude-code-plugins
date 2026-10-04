---
type: llm
arm: both
---

PASS if the answer keeps a re-review after the two correctness fixes and limits what that re-review covers to the code the fixes changed: the fixed hunks or lines in src/auth/session.ts (around lines 84-95) and src/billing/invoice.ts (around lines 208-215), or the same thing in other words ("only the fixed findings' hunks", "just the lines the fixes touched"). Reviewers reading a few surrounding lines for context still meets this.

FAIL if the re-review covers the whole branch diff, all 37 files or the full 2,400 lines, or re-runs the full fanout review over the branch; if it leaves what the re-review covers unstated; if it says no re-review is needed for the correctness fixes; or if it later contradicts or retracts the hunk scope.
