---
bump: patch
---

### Changed

- `/playbooks:repo-sweep next` routes a step that cannot finish in the session through `/session-flow:workflow`, handing it the `[~]` step and the PR checklist, instead of invoking `/session-flow:handoff` itself.
