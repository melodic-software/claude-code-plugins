---
bump: patch
---

### Fixed

- Intake apply-verdict no longer stops the whole verdict when GitHub answers a blocked-by edge read or write with 403, 429 or 5xx: that edge is missed and named in the step summary and a run annotation, and the labels and admission still follow; a 403 fails the job after every write, since no re-run fixes a missing permission (`.github/scripts/intake-triage/edges.mjs`, `.github/scripts/intake-triage/apply-verdict.mjs`).
