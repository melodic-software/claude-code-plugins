---
bump: minor
---

### Changed

- The `local-file` findings buffer moves to `findings-buffer/findings.jsonl` under the git common directory, so every worktree of a clone reads and writes one file; `read.sh` still returns rows from the old per-worktree `.work/buffer/findings.jsonl` (#12907).
