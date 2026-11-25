---
bump: patch
---

### Fixed

- The behavior-probes runner removes the `~/.claude/projects` folder a probe session created
  when, after its transcript is collected, the folder holds only empty directories such as the
  auto-memory `memory` folder. A folder holding any file is left as it was.
