---
bump: patch
---

### Fixed

- video-digest's `watch-state.js close` (and `check-watch-outcomes.js`) now fails a slice whose research gate fails, through a new blocking `research-complete` outcome check that is skipped only when the watch ran with `--skip-research`. The research gate's docs now name `research/findings/*.md`, the path the gate counts, and no longer allow findings inline in `RESEARCH.md` ([#6814](https://github.com/melodic-software/claude-code-plugins/issues/6814)).
- video-digest's `close` now also sets the slice `README.md` frontmatter `status:` to `complete`, so it matches `watch.json` ([#6823](https://github.com/melodic-software/claude-code-plugins/issues/6823)).
