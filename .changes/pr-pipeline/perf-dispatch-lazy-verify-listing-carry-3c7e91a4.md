---
bump: patch
---

### Changed

- pr-feedback-dispatch.yml and pr-unblock-dispatch.yml no longer run a step that fetches pr-merge's
  carried artifact listing on every run. `verify-cap.mjs` runs `listing-carry.mjs` (provenance
  checks unchanged, the same 2-minute limit and its own api-calls notice) on the job's first
  FAIL-cap read only, so a run that skips before any FAIL-cap read spends none of the carry's
  calls. A failed fetch warns, and the reader lists every page as before.
