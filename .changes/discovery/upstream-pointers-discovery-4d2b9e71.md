---
bump: patch
---

### Fixed

- The research discipline no longer calls WebFetch truncation silent: a partial in-context read is treated as the same trigger as a size error, with the WebFetch tool-behavior section as its anchored pointer.

### Changed

- Restated Claude Code specifics (subagent model resolution order, resume behavior, the Explore thoroughness values, the `${CLAUDE_EFFORT}` level list, tool-filter wording, the bundled `deep-research` description) are replaced with anchored pointer records dated 2026-10-11 across the research, explore and trace-intent skills, the researcher and intent-tracer agents, and the parent contract. The research skill now detects an unsubstituted effort placeholder by its literal `${` prefix.
