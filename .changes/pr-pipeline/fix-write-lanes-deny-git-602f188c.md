---
bump: patch
---

### Fixed

- Write lanes deny git commands: they reach git only through the base wrappers. In `merge-base`
  mode, whose skill resolves the merge with git, the lane denies git's global options, the
  subcommands that read config or reach a remote, and the flags or paths that read a file outside
  the index (including `blame` and `grep`) or run a diff or text-conversion program
  ([pr-run-activity.md](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md)).
