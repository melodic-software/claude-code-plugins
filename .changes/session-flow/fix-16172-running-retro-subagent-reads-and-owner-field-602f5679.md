---
bump: patch
---

### Fixed

- `/session-flow:running-retro`: the analysis subagent reads local files with the Read or Grep
  tool, never a shell command; when the transcript is unreadable, its Subagents dir slot reads
  `not available` and it neither reads nor lists that directory; and the presented findings give
  each skill-fit gap an `Owner:` field or Owner column naming `<plugin>:<skill>` or
  `no owner found`.
