---
bump: minor
---

### Changed

- `work-unblock` also runs its sweep when a `work-resolve-issue` run on main in this repository completes, whatever it concluded, so a finished issue run admits the next deferred issue at once instead of at the next hourly sweep. A run in which no job ran (a label other than `agent-ready`) starts no sweep. The sweep reads no field of that event's payload and checks no closer; the token broker allows a re-run only to a listed human.
