---
bump: patch
---

### Fixed

- **`/docs-hygiene:compress` runs each lint-gate step as its own plain command.** Each copy, status read, hash, lint run, restore and delete is a separate Bash call, with no command chains, shell functions or multi-line scripts and no `cd` inside one (a plain `cd` to the repository root as its own call is allowed, so a `--repo` pass lints from the worktree it edited), so a permission system that refuses compound calls no longer leaves the lint gate unrun. Each pre-lint copy is kept until the check after that lint run and any restore it calls for are done. The lint baseline is now named as the step before the snapshot and the first edit, and compress never probes for a linter the repository's command does not name ([#19128](https://github.com/melodic-software/claude-code-plugins/pull/19128) post-merge suite).
