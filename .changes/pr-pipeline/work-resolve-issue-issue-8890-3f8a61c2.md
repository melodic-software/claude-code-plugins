---
bump: patch
---

### Fixed

- The fix-docs dispatcher no longer dispatches a PR again after a `pr-refine fix-docs #<n>` run for it completed without posting a check. Before, a run that stopped at its trigger gate, emitted an empty head or failed before its report was dispatched again on every push to main, and a same-repository PR stopped at the trigger gate took a dispatch slot each time. A PR whose only run was lost (`cancelled`, `timed_out` or `startup_failure`) gets one more dispatch, and none after a second lost run. The dispatcher reads this from the run listing it already reads for its in-flight guard, so it makes no new call (`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`). ([#8890](https://github.com/melodic-software/claude-code-plugins/issues/8890))
