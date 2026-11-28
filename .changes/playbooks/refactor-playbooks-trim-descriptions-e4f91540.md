---
bump: patch
---

### Changed

- Backfilled 20-query invocation probes for `playbooks:{boris,fable-5,repo-sweep,skill-authoring}` and trimmed frontmatter descriptions across all five `playbooks` skills (`boris` 519 -> 349 chars, `fable-5` 984 -> 343 chars, `repo-sweep` 559 -> 320 chars, `skill-authoring` 606 -> 347 chars, `update` 315 -> 148 chars; total 2983 -> 1507 chars, -1476 chars) while preserving all modes, `claude-api` overlap routing, model-adaptation coverage, and maintainer-only `update` posture.
