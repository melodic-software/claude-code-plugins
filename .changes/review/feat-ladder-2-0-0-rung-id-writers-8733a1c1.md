---
bump: major
---

### Changed

- `/review:audit-enforceability` writes the enforcement ladder 2.0.0 rung ids: `action-guard` replaces `hook` and `automated-review` replaces `llm-only`, in the stub's `rung:` field, the stage map, the default for an empty rung and the skill's guidance. The writer's `--classes` set no longer accepts `hook` or `llm-only`, so a caller still sending either id gets the closed-set refusal (exit 2).
