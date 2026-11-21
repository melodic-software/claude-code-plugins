---
bump: minor
---

### Added

- Both hosted review callers' gates defer a first attempt (`defer: "true"`, `defer-job: review`) while the GITHUB_TOKEN window is projected to run short before the review ends, reading their horizon from the new `defer-run-minutes-review` (github-token default 11, the p90 of 418 hosted review runs) through `pr-pipeline.yaml`'s `limits.api` over `rate-limits.json`. Their stop notice now prints `cause=<cause> reset=<epoch>`. The lost-run reconciler reads that notice: it waits until a minute past the reset, then re-runs the deferred run once, recorded, in its own band of at most 12 re-runs a pass beside the 3 places other recovery takes; the reconciler workflow uploads up to 15 records a pass. The re-run's attempt 2 never defers ([#17460](https://github.com/melodic-software/claude-code-plugins/issues/17460)).
