---
bump: patch
---

### Changed

- `/work-items:work` adds the `umbrella` stop code, for an issue whose work is its open sub-issues. The issue lane takes it off `agent-ready` with a visible failed marker and hands it to no person. The lane had sent [#6052](https://github.com/melodic-software/claude-code-plugins/issues/6052), split into sub-issues, to `needs-human`.
