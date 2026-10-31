---
bump: patch
---

### Changed

- pr-feedback-dispatch.yml and pr-unblock-dispatch.yml no longer run a step that fetches pr-merge's
  carried artifact listing on every run. `verify-cap.mjs` fetches it through `listing-carry.mjs`
  (provenance checks unchanged) on the job's first FAIL-cap read only, so a run that skips before
  any FAIL-cap read spends none of the carry's calls. A failed fetch warns, and the reader lists
  every page as before.
- `verify-cap.mjs` runs the FAIL-cap reader as a child process the event loop keeps serving,
  instead of under `spawnSync`. A killed read still answers `ETIMEDOUT` and the round still runs
  under its own caps. Runs whose read was killed at the limit then failed the dispatch with
  `fetch failed`, so the next run at that head paid for the read again; a blocked loop leaving the
  job's connections unserved is the suspected cause.
