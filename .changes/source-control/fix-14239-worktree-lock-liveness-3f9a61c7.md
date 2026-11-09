---
bump: patch
---

### Fixed

- `worktree-claim.sh stale` no longer calls a lock stale while a running Claude Code process holds its session, however old the transcript is, so a worktree reap cannot remove a tree under a quiet live session. A dead or pid-reused registry entry falls through to the transcript-age check, and a missing or malformed session registry, or a host where the process start time cannot be read, reports "not provable". `--batch` reads the registry once per run.
