---
bump: patch
---

### Fixed

- `/testing:cleanup`'s classifier and skeptic briefs let the subagent search with read-only `grep`, `rg` or `find` through Bash when the session has no Grep or Glob tool, so a search can still back a citation. The subagent stays read-only and runs no other command ([#11815](https://github.com/melodic-software/claude-code-plugins/issues/11815)).
