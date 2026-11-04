---
bump: patch
---

### Changed

- **`/prototype:explore-directions` and `/prototype:pressure-test` resolve the view medium through the shared resolver** ([#12684](https://github.com/melodic-software/claude-code-plugins/issues/12684)). Each runs `lib/view-settings.mjs resolve` with its own lane and prints the report line and any notice. Each acts on the resolution's `publishes` and `page` fields instead of naming medium values. They no longer read the retired `~/.claude/rendered-views.md` or `.claude/rendered-views*.md` layers themselves; the resolver turns those into notices.
