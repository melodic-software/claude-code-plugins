---
bump: minor
---

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/harness-ops.yaml`, read from the default branch by `lib/read-verification.sh` and validated by the new `schemas/harness-ops.schema.json`. `/harness-ops:audit-install-state` follows it for its fresh-context cross-review (`strict` dispatches it for a single-agent run too), and `/harness-ops:changelog` for its local verifier, in `diff` and in `apply`'s re-check of saved rows. Under `light` and `off` neither dispatches; each records `verification: skipped (<level>)` and marks what it would have checked `unverified`.
