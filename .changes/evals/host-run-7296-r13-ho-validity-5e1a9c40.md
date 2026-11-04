---
bump: patch
---

### Changed

- `plugin-eval`'s sandbox reference says when a run needs `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`: a case
  that invites saving state otherwise sends the no-plugin arm into a denied auto-memory write.
