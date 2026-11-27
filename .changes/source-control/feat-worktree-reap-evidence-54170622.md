---
bump: minor
---

### Added

- `worktree-include.sh copy` records what it carried in the worktree's `carried.index` (a git index holding stat and object ids, no blobs). `diff --worktree-only` judges against it, so a later edit to main's copy no longer blocks a finished worktree: `MODIFIED` is a carried file edited in the worktree, `NEW` an included file never carried, a carried file deleted in the worktree is no loss, and a worktree with no manifest is compared with main as before, one `NO-MANIFEST` row marking it only when a copy differs. `sync-back` refuses (exit 2) a file main changed since the copy.
- `worktree-claim.sh stale` proves a session-less `lane active on <host> since <utc>` lock stale when it is from this host and older than the idle window, every live registered session records a cwd outside the path, no process's cwd is at or under it, and no transcript changed within the window (at any depth, so subagents count) names the path in any string, a cwd, a file path or a command. An unreadable recent transcript, and any host other than Linux, leave it not provable. The session registry read takes each entry's optional `cwd`.
- `/source-control:worktree review` reads the newest nightly reap run file's `review` rows, writes a cited verdict per worktree to `reviews/<run-utc>.<review-utc>.jsonl` beside it, and resolves a row only by a push or `sync-back`. It never deletes.
