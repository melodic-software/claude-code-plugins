---
bump: patch
---

### Fixed

- audit-skill-visibility says its `CLAUDE_CODE_MAX_CONTEXT_TOKENS` rule (applied only with `DISABLE_COMPACT`) assumes a model ID Claude Code recognizes, points at the model config section that lists which IDs need what, and tells the operator to pin `--context-window` for a gateway alias, which since Claude Code 2.1.325 includes unrecognized `claude-` IDs (#16035).
