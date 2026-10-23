---
bump: minor
---

### Added

- `merge.gate-candidate-minutes` (a whole number of minutes; absent is no limit): how long one candidate's gate in `pr-merge.yml` may spend reading. Past it the gate starts no further read and the candidate is reported `unknown:candidate-deadline` (exit 11), never ready; a write already started finishes, and the loop goes on to the next candidate within `merge.gate-budget-minutes`. The first candidate a run stops is recorded in the gate cursor as deferred and gated first in the next run under `merge.gate-deferred-minutes` (20 here; absent is no limit), so a pull request whose gate always runs past the limit still gets a longer gate. One stopped at that ceiling gets a warning annotation and goes back to the capped rotation, never deferred again. Set to 4 here, so one slow candidate no longer holds the serialized merge queue for 20 minutes or more.
