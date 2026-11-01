---
bump: patch
---

### Fixed

- `orchestrate`'s gotchas no longer tell you to read a depth rejection's error text, since a
  subagent at the depth limit may get no error; they point at the sub-agents depth section.
  `reconcile` no longer says every spawned subagent owns a task list, and points at the
  tools-reference section on task-tracking tools in subagents
  ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
