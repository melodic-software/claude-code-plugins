---
bump: minor
---

### Added

- The merge gate takes `--candidate-deadline-seconds` with `--authority pr-merge`: its two read phases (the merge policy, then the verdict) start no command past the deadline and the gate exits 11 with an `unknown:candidate-deadline` error, before any further write. Writes are never bounded, so a merge-queue write is never cut short. Without the flag nothing changes.
