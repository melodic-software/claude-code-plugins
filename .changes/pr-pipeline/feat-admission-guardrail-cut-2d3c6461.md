---
bump: minor
---

### Changed

- An issue whose Size, Complexity or Uncertainty field is empty, or was last set by an account that is neither a listed human nor the lanes App, is no longer refused with `not-assessed`: the field reads as Size `small`, Complexity `medium` or Uncertainty `known`, and the run goes ahead at that budget. The config check rejects an `issue-dimensions` table that lacks one of those keys, or whose `small` size is `split`.
- This repository's Uncertainty `knowable` maps to `run`, so a Knowable issue runs instead of skipping with `research-first`. Unknown still skips with `probe-first` and Large with `split-required`.
- `work-resolve-issue` no longer adds `Hold: a human merges this` for `work-class: structural`; untrusted-provenance work, `merge: human` and the denied-path diff still carry it.
- intake-triage holds an issue for cost only when the charge is one no diff shows: a new paid service or subscription, a plan upgrade, or an account, organization or repository billing setting. A charge a diff shows (IaC, runner labels or cron, model, effort or turn flags, new secrets) gets no `cost` flag; the merge-time cost hold catches it.

### Removed

- The `labeled-after` predicate key, its schema property and the issue update-time read that served it. The `work-resolve-issue` lane's go-live cutoff is gone, so an issue labeled `agent-ready` at any time starts a run.
- `not-assessed` as an issue-dimension skip: `report-skip` and the write file's `dimension-skip` input no longer accept it. fix-ci's neutral `not-assessed` check is unchanged.
