---
bump: patch
---

### Changed

- pull-request: the monitor entry and per-iteration checklists move from SKILL.md to
  `reference/monitor.md`, which `monitor`, `comments` and `full` already read, so `create` and
  `ready` loads no longer carry them. The text moves verbatim except three paths, now written
  `<skill-dir>` and `<plugin-root>` as reference files require. The body drops from 51,224 to
  35,846 bytes; SKILL.md keeps a Monitor entry section that sends Phase 3 to the moved
  checklists before any polling. Two eval cases cover the moved text: a behavior finding gets a
  failing test first, and a person's review thread stays unresolved.
