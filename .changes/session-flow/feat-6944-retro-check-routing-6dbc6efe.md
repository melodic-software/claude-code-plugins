---
bump: minor
---

### Changed

- **`/session-flow:retro` routes check-worthy findings to the skills that own checks.** The catalog gains an Owner skills table: mechanical mistakes go to `/review:audit-enforceability`, missing automation to `/harness-config:audit-automation-gaps`, instruction findings to `/harness-config:audit-instructions` and `/harness-config:unhobble`, token-heavy CLI output to `/developer-experience:build-cli`, and agent-doc findings to `/docs-hygiene:write-for-agents`, each named only when installed. Retro proposes a check, never adopts one: on the first occurrence of a policy-class mistake (irreversible, public, security) and on a repeat for a behavior correction, and no check is a valid outcome. Codify mode now points at the same table, and the placement tree no longer sends enforcement gaps to prose.
