---
bump: patch
---

### Changed

- The `control-claude-code` control skill records its launch model: no per-run data directory,
  since a run reuses the signed-in Claude Code config directory; sessions run side by side under
  distinct names; one new session holder per drive. Its Ready states that port ownership and
  credential validity are not exposed.
