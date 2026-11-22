---
bump: patch
---

### Changed

- Lanes and the dead-code shapes point at `docs/conventions/ecosystems/<ecosystem>.yaml` for a repository's commands. The shared copies (`reference/ecosystem-resolution.md`, and the git-hook library where this plugin carries it) name `docs/conventions/ecosystems/<ecosystem>.yaml` as the home of a repository's ecosystem records, with the legacy `.claude/ecosystems/` still read for a record absent there.
