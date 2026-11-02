---
bump: patch
---

### Changed

- The vendored git-hook check library now counts only the lines a merge's conflict resolution adds
  as a merge commit's changed lines. This plugin's own hooks do not read changed lines, so they
  behave as before.
