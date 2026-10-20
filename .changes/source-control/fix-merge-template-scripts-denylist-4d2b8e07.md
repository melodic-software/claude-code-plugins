---
bump: patch
---

### Fixed

- pull-request merge: the guarded merge template and the merge script's guard now carry the
  auto-mode entry's scripts clause, `^scripts/(?!.+\.(txt|md)$)`, a denylist in place of the
  executable-extension list, so a command printed by the script matches the entry.
