---
bump: patch
---

### Changed

- Setup names `docs/conventions/ecosystems/<ecosystem>.yaml` as the record it drafts commands for, in place of `.claude/ecosystems/`. The hook library's record note also finds a record at `docs/conventions/ecosystems/`; hooks still never run a record's command. The shared copies (`reference/ecosystem-resolution.md`, and the git-hook library where this plugin carries it) name `docs/conventions/ecosystems/<ecosystem>.yaml` as the home of a repository's ecosystem records, with the legacy `.claude/ecosystems/` still read for a record absent there.
