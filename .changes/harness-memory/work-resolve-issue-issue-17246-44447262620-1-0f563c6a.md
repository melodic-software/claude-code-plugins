---
bump: minor
---

### Added

- `/harness-memory:audit` accepts the target-scope contract's forms (`--repo`, `--repos-from`, `--owner`, `--fleet`, `--skip`) for `audit`, `report` and `fix`. It runs one pass per repository from that clone's root and keeps each repository's report under that clone's own state key. `fix` works one repository at a time in the main session, with one worktree and one pull request per repository for tracked files. A rule repeated across several repositories' `CLAUDE.md`, `AGENTS.md` or `.claude/rules/` files is reported as a candidate for user scope or the standards repository. With no target form the audit runs on this project, as before.
- The plugin ships `reference/target-scope.md`, a generated copy of the target-scope contract.
