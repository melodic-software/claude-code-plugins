---
bump: patch
---

### Changed

- `reference/rendered-view.md` step 3 sends every view lane to the shared medium resolver, discovery included, and no longer lists `~/.claude/rendered-views.md`, `.claude/rendered-views.md` and `.claude/rendered-views.local.md` as files to read. The `terminal` delivery points at the resolver's report line in place of naming a layer.
