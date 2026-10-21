---
bump: minor
---

### Changed

- The held cap pauses the issue lane like the WIP cap: on or after `wip.pause-from`, at or over
  `wip.held-cap` held lane PRs, work-resolve-issue starts no run and work-unblock re-fires none.
  It used to alert only. This repository sets `held-cap: 10` (was 60).
- check-wip-cap publishes `pause_reason` (`wip`, `held-cap` or `wip,held-cap`) and, on every
  pause, logs `admission paused: reason=... countable=... wip_cap=... held=... held_cap=...` as a
  `::notice` and in the step summary, so pauses can be counted.
- `docs/adr/**` joins this repository's `floor-paths`: a lane PR that changes an ADR scores HIGH
  and waits for a human.
