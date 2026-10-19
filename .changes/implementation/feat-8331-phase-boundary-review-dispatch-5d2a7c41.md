---
bump: minor
---

### Added

- A plan phase tagged `Review: architecture`, `security`, `code-design` or `concurrency` now gets that review at its boundary. `/implementation:implement` and `/implementation:implement-dispatch` invoke `/review:quality-gate architecture`, `security`, `code-design` or `slice concurrency` with the previous phase-boundary commit as `--base`, the plan's `Quality bar:` line when it has one, `--report-only`, and, for a worker's worktree, `--worktree`, and pass no rationale. The sequence is review, fix inside the phase fence, one re-review against the same base, then the acceptance verdict last. Any CRITICAL on the re-review goes to `DEVIATIONS.md` as a blocking `human-decision` and is escalated once, never looped. An untagged phase gets no review. Under an unattended permission mode that denies the review's worktree reads, the run logs the review as not run (`unverified`), lists it in the final report, and continues to the phase-verifier.
