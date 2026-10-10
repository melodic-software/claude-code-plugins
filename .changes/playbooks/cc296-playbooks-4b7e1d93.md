---
bump: patch
---

### Fixed

- **`skill-authoring` no longer ships skills that abort on a permission rule.** The precomputed-context guide called `!` injection preprocessing rather than a tool call and offered the `|| echo` fallback as the only guard, but Claude Code checks every injected command against the consumer's permission rules and, outside auto mode, stops the skill from loading when they do not allow it, which no fallback can catch. The guide now requires each injected command to be pre-approved in the skill's own `allowed-tools` (every subcommand, fallback included), designs for the default permission mode, and moves a command a consumer's deny or ask rule could match into a normal body step, with a pointer record to the skills page's permission-checks section.
