---
bump: minor
---

### Added

- `scripts/worktree-include.sh` owns `.worktreeinclude` copy, diff (`--worktree-only`, `--unified`), and validated `sync-back` over one NUL-safe `git ls-files -o -i -z --exclude-from` + `git check-ignore --stdin -z` intersection, shared by `worktree-create.sh`, `pull-request/reference/create.md`, `worktree/context/cleanup.md`, and `worktree-reap.sh`.
- `scripts/worktree-reap.sh` owns unattended multi-root worktree reaping inside `source-control`, composing `worktree-root-resolve.sh --all`, `landed-work.sh --stats-file`, `worktree-include.sh diff --worktree-only`, and batched `worktree-claim.sh stale --batch`, honoring `userConfig.worktree_reap_after_hours`, counting both `project` and `local` scope plugin records, and preserving lock rollback and `/proc` double-scan guards.
- `scripts/worktree-root-resolve.sh --all` (`worktree_root_collect_includes` and `worktree_root_list_all`) enumerates global, unconditional `[include]`, and readable `[includeIf]` worktree roots for `worktree-discover.sh`, `worktree-root-doctor.sh`, and `worktree-reap.sh`.
- `scripts/landed-work.sh --stats-file <path>` writes `gh_calls` and `rate_limited` counters.
- `scripts/worktree-claim.sh claim --all-unclaimed --include-gone` opts into claiming `[gone]` upstream branches.

### Fixed

- `scripts/landed-work.sh` enforces strict 9-level risk precedence (`notgit > bare > superseded > STRANDED > UNKNOWN > in-progress > dirty > landed > ok`), includes untracked files in `dirty`, maps unreadable status (`?`) to `UNKNOWN`, and proves base ancestry (`landed=yes`, `method=ancestor`) when `unpushed == 0` so `--no-track` merged branches qualify as landed.
- `scripts/worktree-claim.sh` uses one 4-state lock classifier (`unlocked`, `ours`, `foreign`, `reasonless`) mapping reasonless manual locks to exit `4` across `claim`, `check-enter`, `release`, and `handover`, reporting `LOCKED_NO_REASON` in `report`, and skipping `[gone]` branches and reasonless locks in `claim --all-unclaimed`; `skills/worktree/context/status.md` now defines `unclaimed` as `locked=no`.
