---
bump: patch
---

### Security

- `reap-project-plugin-records.sh`, which the worktree-remove gate runs, sends its git calls through `hook::git_untrusted`, so reading and restoring the worktree's `.claude/settings.json` no longer starts a `core.fsmonitor` command or git hook named in that repository's config.
