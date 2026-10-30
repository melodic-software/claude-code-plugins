---
bump: minor
---

### Changed

- `/source-control:worktree cleanup` run outside a repository now removes worktrees across repositories ([#11120](https://github.com/melodic-software/claude-code-plugins/issues/11120)). It finds the repositories `audit` finds, shows the candidates grouped by owning repository behind one confirm, and runs every guard and each removal with `git -C` on the owning repository, leaving the caller's working directory unchanged. Stranded, superseded and unknown rows stop as they do in a single-repository run, and `--dry-run` removes nothing.
