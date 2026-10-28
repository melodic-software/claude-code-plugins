---
bump: minor
---

### Changed

- The issue lane routes each stop by one table, `.github/scripts/work-resolve-issue/stop-routes.json`, instead of adding `needs-human` on every stop. `hold` (the human-gated label and escalation marker) is kept for a pushback, a run's `intent-change`, `design-change`, `security-risk` or `cost-risk` code, a stop with no code, an issue edited after `agent-ready`, a patch or output refusal that may be a credential shape, and a run whose patch collector refused a file left at a stub name such as `.npmrc` or `.env` (the new `collect-refused` input of the write file carries the read file's `scan-collect-refused` to report-outcome). A protected path or a run's `host-only` code adds `host-run` and removes `agent-ready`. A crash, an apply fault, a moved PR head and an unfinished or failed check keep `agent-ready` with an `outcome=retry` marker naming the branch, and work-unblock restarts the issue. A retry past the new `limits.stop-retries` (default 2), or a spent turn cap, removes `agent-ready` with no label and an `outcome=failed` marker, which the maintenance monitor reports as signal 9.

### Added

- `limits.stop-retries` in `pr-pipeline.yaml`: restarts after a retry-routed stop since a listed human last added `agent-ready`, 0 to 5.
