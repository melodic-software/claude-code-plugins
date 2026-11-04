---
bump: patch
---

### Fixed

- **The retired `~/.claude/rendered-views.md` notice no longer points at a `medium` option this plugin does not ship.** The shared medium resolver adds "; per user, the <plugin> plugin's medium option also works" only for a lane whose plugin ships a `medium` userConfig option, which each lane registration in `lib/view-registry.mjs` now records as `hasMediumOption`. `generate` now prints every notice as the resolver gives it, in place of rewriting that notice by hand.
