---
bump: patch
---

### Changed

- The retrieval role's effort now records an upstream basis in model-config's effort table, and the orchestrator's `high` effort, the worker's `mechanical` model and the retrieval model give the task table in Anthropic's model-choice guide as the context for their judgment. No resolved value changes.
- The routing rubric records the owner's decision that no role routes to Haiku, with the guide's Haiku rows as the disagreeing source.
