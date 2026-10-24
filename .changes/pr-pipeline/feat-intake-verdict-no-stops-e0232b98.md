---
bump: minor
---

### Changed

- Intake triage stops an issue for a person only on intent or security. A hold label the lanes App set on an earlier run gives way to a clean verdict and is taken off; a hold from the triage run's own escalation, a listed human or an unread setter still holds. A `needs-triage` the triage left no longer keeps a clean verdict from `status: ready` and is taken off after the verdict. An issue field a listed human set to another value is kept and is the value admission reads, without a hold; one from any other setter still holds. GitHub keeping other field options than `models.issue-dimensions` maps fails the run without adding `status: needs-decision`. Whenever the verdict sets `status: needs-decision`, the reasons go on the issue in one lanes App comment edited in place, not only in the step summary (`.github/scripts/intake-triage/apply-verdict.mjs`).

### Added

- Intake writes a native blocked-by edge for each open issue in the repository the triage names on a new `Blocked by: none|#N[, #M]` verdict line, before admission reads the blockers; only `#<number>` tokens count, the issue itself, pull requests, closed and other-repository issues and existing edges are skipped, and at most 50 are written (`.github/scripts/intake-triage/edges.mjs`, `.github/workflows/intake-triage.yml`).
