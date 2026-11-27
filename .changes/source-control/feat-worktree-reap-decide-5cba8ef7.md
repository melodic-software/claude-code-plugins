---
bump: minor
---

### Added

- `worktree-reap.sh` writes a run record, `runs/<utc>.jsonl` beside its log: one line per examined worktree with its facts, verdict (`remove`, `keep` or `review`), reason and outcome, and one closing run line with wall time per phase, bytes removed, the memory peak and the `.work` items with no file modified in 30 days. One `decide` function sets every verdict; `remove` needs every guard to pass, and any other combination reads `keep unknown`. Run and review files older than 14 days are deleted at start, and `--report [<run-file>]` prints a run's report.

### Changed

- The reap's reasons split: `unsafe-work` becomes `stranded` and `unknown-work` (both `review`), `dirty` and `not-landed`; `carried-file` becomes `carried-edited` and `no-manifest` (both `review`) and `carried-unreadable`. Worktrees of a repo whose fetch failed or that declares a Workspace `down` are counted per worktree.
