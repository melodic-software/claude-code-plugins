---
bump: patch
---

### Fixed

- leave release fragments out of the repo-mode sweep targets

  `/multi-agent:audit-defaults repo` now leaves `.changes/` release fragments out of its target list, as it already did changelogs, so a release no longer changes which files the sweep covers. The `multi-agent:drift-audit` workflow's repo-mode sources of record name the models overview at its current address, `models/overview`, which the platform docs index lists; the old `about-claude/models/overview` address was read as unread.
