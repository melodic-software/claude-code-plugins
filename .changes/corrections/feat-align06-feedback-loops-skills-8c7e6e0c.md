---
bump: minor
---

### Changed

- `codify rules` gives each `delete` a reason (derivable, no-op, duplicate or stale) with what shows it, holds a misplaced rule with a hand-off to `/instruction-placement:audit`, and points stale and conflicting rules to `/harness-config:audit-instructions`.
- `codify`'s `## Next` names `/toolchain:ratchet` and `/architecture:enforce-boundaries`.
