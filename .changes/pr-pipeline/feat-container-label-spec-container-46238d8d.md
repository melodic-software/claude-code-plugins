---
bump: major
---

### Changed

- `check-born-triaged` treats `spec-container` as the container label when `tracker.config.container_label` is absent or empty, matching the work-items default. Intake triage, the triage sweep, intake re-entry, the WIP cap, `check-blockers` and `label-unblocked` skip an issue carrying `spec-container` or a `wayfind:` label; an issue carrying only `work-map` is no longer skipped by default.
