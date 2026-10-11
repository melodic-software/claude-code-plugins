---
bump: patch
---

### Fixed

- go-faster: session-work no longer counts paged reads or re-reads of changing output as repeats. `findings.py transcript-counts` keys a Read on its path plus any `offset`, `limit` or `pages`, counts a call as a repeat only when its result also matches the earlier one, and never counts a read of a background task's `tasks/<id>.output` file. Identical calls whose results the transcript does not hold are reported apart as `unverified_repeated_reads` and `unverified_repeated_commands`, which the sweeper records as `later`, never as an "Adopt now" item.
