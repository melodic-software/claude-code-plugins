---
bump: patch
---

### Security

- The end-of-turn hook runs its git-hook entry (`--worktree`) with `core.fsmonitor=false` and `core.hooksPath=/dev/null` in the child's environment (`hook::git_untrusted_env`, through `GIT_CONFIG_COUNT`), so the entry's git calls no longer start a `core.fsmonitor` command or git hook named in the repository's config.
