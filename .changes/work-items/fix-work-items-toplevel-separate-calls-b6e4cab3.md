---
bump: patch
---

### Fixed

- **Work-items snippets no longer embed `$(git rev-parse --show-toplevel)`.** The tracker, schedule, evaluator and backfill path fallbacks in `attend-queue`, `scan-todos`, `setup`, `ship`, `track`, `triage` and `work` now write a literal `<project root>`, which the shared tracker reference's new "Project root" section resolves in its own Bash call (`$CLAUDE_PROJECT_DIR` when set, else the repository root). This is the worktree-isolation rewrite `decompose` and `track add` got for [#6929](https://github.com/melodic-software/claude-code-plugins/issues/6929).
