---
bump: minor
---

### Added

- `worktree-include.sh copy` records what it carried in the worktree's `carried.index` (a git index holding stat and object ids, no blobs). `diff --worktree-only` judges against it, so a later edit to main's copy no longer blocks a finished worktree: `MODIFIED` is a carried file edited in the worktree, `NEW` an included file never carried, a carried file deleted in the worktree is no loss, and one `NO-MANIFEST` row marks a worktree with included files and no manifest. `sync-back` refuses (exit 2) a file main changed since the copy.
- `worktree-claim.sh stale` proves a session-less `lane active on <host> since <utc>` lock stale when it is from this host, older than the idle window, and no live session's cwd and no transcript changed within the window (at any depth, so subagents count) works at or under the path. Off Linux it stays not provable. The session registry read takes each entry's optional `cwd`.
- `/source-control:worktree review` reads the newest nightly reap run file's `review` rows, writes a cited verdict per worktree to `reviews/<utc>.jsonl` beside it, and resolves a row only by a push or `sync-back`. It never deletes.
