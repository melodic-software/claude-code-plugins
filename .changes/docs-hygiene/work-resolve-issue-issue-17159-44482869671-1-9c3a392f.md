---
bump: minor
---

### Changed

- For a rule that must hold every time, `/docs-hygiene:write-for-agents` now names the call `/corrections:codify "<the rule>"` for the user and, when that skill is available, leaves the choice of mechanism to it. Without it, the skill proposes the strongest mechanism that can decide the rule and says the proposal is unproven. It no longer names a hook, deny rule, CI check or permission policy itself.
