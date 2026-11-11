---
bump: patch
---

### Changed

- The report skill keeps its rule that `preload_token` is the only evidence a preloaded skill reached the agent, and points at the subagents page's "Preload skills into subagents" section for what happens to a `skills:` entry that does not load instead of restating it. Its Agent-result basis link now names the "Subagent output scanning" section. No behavior change.
- The parent contract's preload record ("Harness facts the dispatch design rests on") now states our decision, that only the liveness token shows a preload loaded, instead of restating harness behavior, and is re-dated. The explorer, researcher and intent-tracer agents, the explore and trace-intent skills, and both dispatch references keep their one-sentence rule and cite that record by heading instead of saying a failed preload is skipped silently or carrying their own docs pointer. No behavior change.
