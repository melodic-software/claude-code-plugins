---
bump: minor
---

### Added

- `/session-flow:orient zoom-out [--days <N>]` reports the whole effort: when it started, one row per session from the handoff chain grouped by day, what runs now, the near and long term from the plan, handoffs and tracker, and the open decisions with options and a recommendation. It resolves the effort boundary from the spec container, then the branch, the plan file and the topic slug, and names the one it used. Days with no handoff are filled from git, merged pull requests and `/session-flow:recall`. Every claim carries a source label, and a disagreement between sources points to `/session-flow:reanchor`. It writes nothing. ([#7341](https://github.com/melodic-software/claude-code-plugins/issues/7341))
