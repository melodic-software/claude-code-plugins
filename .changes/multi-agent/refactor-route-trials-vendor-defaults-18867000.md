---
bump: minor
---

### Changed

- While trials run, `/multi-agent:route vendors` tries the first model each vendor's `external-agents models` lists, at that model's default effort, instead of the model and effort a benchmark board leads with, and fetches no support-only or provider-own board.

### Fixed

- `vendor-state record` no longer fails on Windows when a concurrent record holds a file open in the trial folder it is removing; the rename is retried briefly.
