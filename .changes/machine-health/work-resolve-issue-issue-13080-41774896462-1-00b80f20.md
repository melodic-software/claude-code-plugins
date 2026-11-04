---
bump: patch
---

### Changed

- **The shared view registry records whether each lane's plugin ships a `medium` option.** `lib/view-registry.mjs` gains `hasMediumOption` on every lane registration, and the retired `~/.claude/rendered-views.md` notice names the plugin's `medium` option only for a lane where it is set; this plugin's notices are unchanged.
