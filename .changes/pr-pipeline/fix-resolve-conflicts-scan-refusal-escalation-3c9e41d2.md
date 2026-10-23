---
bump: patch
---

### Fixed

- A `resolve-conflicts` round whose scan refused the model's output (a leak-scan block or an oversize patch) now escalates `unresolved-conflict` instead of ending with a failed leg and no escalation. The new `conflict-scan-refusal` job in [`pr-unblock.yml`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/workflows/pr-unblock.yml) runs when the answering leg handed on no patch state, downloads the read runner's scan-refusal markers by name, never a job output, and reads them with `scanRefusal` through [`conflict-scan-refusal.mjs`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/scripts/pr-unblock/conflict-scan-refusal.mjs); `report-escalation` and `report-conflict-status` take its reason. No marker escalates nothing ([#9391](https://github.com/melodic-software/claude-code-plugins/issues/9391)).
