---
bump: patch
---

### Changed

- The triage `evals.json` file is retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Eighteen more native cases cover legacy triage cases 21-36, 38 and 40: the missing-label stop, the objection window and its failed post, a bug already fixed on the default branch, a valid `--config-ref` passed single-quoted, the blocked-by-won't-do bucket, signal items as C5 by rule, an invalid repository repro count, a reporter's own verification, the issue dimensions with the split size and probe-first routes, the human-gated sweep attended and unattended, an outsider item in a lane barred from class labels, and the retired rendered-views file that keeps the board in the terminal. Legacy cases 15, 17, 37 and 39 and the per-user half of 28 are held: each depends on a plugin option value an eval run cannot set.
