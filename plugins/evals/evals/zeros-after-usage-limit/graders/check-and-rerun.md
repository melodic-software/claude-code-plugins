---
type: llm
arm: both
---

PASS if the answer tells the user to check each affected run's `error` field (for example `cases[].arms.with[].error`) before believing the drop, and to rerun the affected cases (for example once the limit resets) rather than call it a regression or flaky cases. A rerun made conditional on that check (rerun once the limit resets if the `error` field names a limit) meets this, as long as the answer does not conclude a regression on the other branch.

FAIL if the answer concludes a plugin regression or flaky cases; says the error field will be null or is not worth checking; points only at logs or the scores; suggests changing the plugin, the graders or the cases; or later contradicts or retracts this.
