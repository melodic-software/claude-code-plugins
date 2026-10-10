---
bump: patch
---

### Fixed

- **The agent-doc surfaces guide no longer says nested CLAUDE.md and path-scoped rules load only on a file read.** `/docs-hygiene:write-for-agents` told authors these surfaces load when Claude reads a matching file, but current Claude Code also loads them when Claude writes or edits one, and counts some single-file shell reads. The guide now says they load when Claude works with a matching file and points at the memory docs for the exact trigger list, with an as-of date and a recheck trigger, so the next change to that list does not make the guide wrong again. The same claim in the `/docs-hygiene:extract-ssot` anti-patterns reference is corrected the same way. The guide's AGENTS.md row no longer says a nested AGENTS.md attaches only on a read, and the guide notes that the changelog and the memory docs disagree on what attaches one, pointing at both.
