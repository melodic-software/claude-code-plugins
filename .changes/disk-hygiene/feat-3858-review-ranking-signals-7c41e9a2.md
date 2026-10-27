---
bump: minor
---

### Added

- `scan` ranks entries for review by three signals read from fields the snapshot already records: `discovery-hint` (`hints`), `sibling-mtime-cluster` (files or directories in one parent whose `mtime_ns` chain within 2 s, likely one operation's output) and `size-collision` (non-empty files of identical `stat_size` in one directory or sibling directories, the target's own files only among themselves, hard links to one object excepted). No path is opened or stat'ed again. Each entry carries `review_rank`: `ranked` with a `position` and the signals and groups that placed it, or `unranked` with a null position. The snapshot's `review_ranking` lists each group with its detail and what each signal reads, and `scan-complete` reports `ranked_entries`, `unranked_entries` and `entries_by_signal`. No eligibility, tick or blocker decision reads the rank, so it changes review order only. The `clean` and `audit` skills present findings in that order.
