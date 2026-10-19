---
bump: minor
---

### Added

- A plan phase tagged `Review: architecture`, `security`, `code-design` or `concurrency` now gets that review at its boundary. `/implementation:implement` and `/implementation:implement-dispatch` invoke `/review:quality-gate architecture`, `security`, `code-design` or `slice concurrency` with the previous phase-boundary commit as `--base`, the plan's `Quality bar:` line when it has one, `--report-only`, and, for a worker's worktree, `--worktree`, and pass no rationale. The sequence is review, fix inside the phase fence, one re-review scoped to the fixed hunks, then the acceptance verdict last. A finding rated CRITICAL again goes to `DEVIATIONS.md` as a blocking `human-decision` and is escalated once, never looped. An untagged phase gets no review. Under an unattended permission mode that denies the review's worktree reads, the run logs the review as not run (`unverified`) and continues to the phase-verifier.
