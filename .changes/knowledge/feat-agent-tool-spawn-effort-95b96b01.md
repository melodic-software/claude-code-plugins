---
bump: patch
---

### Changed

- docpage-digest: verifier A dispatched through the Agent tool now passes its resolved level as the spawn `effort` on a generic spawn and omits it on a pinned named agent, instead of running at the session level.
- map-corpus: the effort gotcha now points at the "Where per-task effort is set" record, which covers both the Agent tool's per-spawn `effort` and Workflow.
