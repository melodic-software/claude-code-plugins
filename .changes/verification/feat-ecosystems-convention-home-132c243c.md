---
bump: patch
---

### Changed

- `/verification:confirm` reads a record's `requires` from `docs/conventions/ecosystems/`, else the legacy `.claude/ecosystems/`. The shared copies (`reference/ecosystem-resolution.md`, and the git-hook library where this plugin carries it) name `docs/conventions/ecosystems/<ecosystem>.yaml` as the home of a repository's ecosystem records, with the legacy `.claude/ecosystems/` still read for a record absent there.
