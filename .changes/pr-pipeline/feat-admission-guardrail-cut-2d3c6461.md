---
bump: minor
---

### Changed

- This repository's Uncertainty `knowable` maps to `run`, so a Knowable issue runs instead of skipping with `research-first`. Unknown still skips with `probe-first` and Large with `split-required`.
- `work-resolve-issue` no longer adds `Hold: a human merges this` for `work-class: structural`; untrusted-provenance work, `merge: human` and the denied-path diff still carry it.
- intake-triage holds an issue for cost only when the charge is one no diff shows: a new paid service or subscription, a plan upgrade, or an account, organization or repository billing setting. A charge a diff shows (IaC, runner labels or cron, model, effort or turn flags, new secrets) gets no `cost` flag; the merge-time cost hold catches it.

### Removed

- The `labeled-after` key from the live config and its schema property, and the issue update-time read that served it. The `work-resolve-issue` lane's go-live cutoff is gone, so an issue labeled `agent-ready` at any time starts a run.
