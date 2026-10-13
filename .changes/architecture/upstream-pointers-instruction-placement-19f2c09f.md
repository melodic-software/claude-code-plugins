---
bump: patch
---

### Fixed

- `/architecture:record-decision` no longer gives two outdated harness behaviors as the reasons for its context-gathering rules (how much command output reaches context, and which git commands a worktree-isolated session refuses). It keeps both rules and points at the live docs sections instead.

### Changed

- The four `map-*` skills that run a collector script now share one `${CLAUDE_SKILL_DIR}` path record in `reference/config.md` § Script paths, with a pointer to the live skills docs, in place of four restated copies of the path-resolution behavior.
