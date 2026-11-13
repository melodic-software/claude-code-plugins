---
bump: minor
---

### Changed

- `/implementation:implement` Step 5's rubber-duck advisor checkpoint now follows the `verification` level: under the default `light` (and `off`) it calls no advisor and the handoff summary says `verification: skipped (<level>)`; `strict` calls it for every change. Set `verification: standard` in `docs/conventions/implementation.yaml` on the default branch to keep it.

### Removed

- `/implementation:implement` Step 5 no longer runs a self-review of the diff, and without the `verification` plugin it no longer self-verifies the outcome against intent: the run states that outcome verification did not run.
