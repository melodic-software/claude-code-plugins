---
bump: minor
---

### Added

- `check-kill-switch` gains a defer gate (inputs `defer`, `defer-minutes`, `resolved-config`): on a first run attempt it stops a job whose work a later run recovers, with cause `defer` and the window's reset, while the GITHUB_TOKEN window's burn rate projected to the job's horizon, or to the reset when sooner, leaves under `defer-project` of the header's limit. It reads no `start-gate` floor, never waits, and never defers a re-run attempt; each deferral logs a `defer` notice naming the cause, the projected share and the reset. `pr-pipeline.schema.json`'s `limits.api` pools admit `defer-project` (github-token default 0.3, 0 turns deferral off) and `defer-run-minutes` (default 15), both defaulted in `rate-limits.json`. Only pr-merge's PR-scoped arm run (`inputs.pr`) defers, with a 6-minute horizon, and its `pr-merge-wake` line reports the deferral and the reset; the sweep, CI Status and pr-dispatch-feedback never defer ([#17460](https://github.com/melodic-software/claude-code-plugins/issues/17460)).
