---
bump: patch
---

### Changed

- work-resolve-issue skips its API-key call (resolve-issue) while `vars.CLAUDE_API_KEYS_DISABLED` is `true`, as it does for a key the credit read holds off. pick-slot's `skip-key` reads the switch, and the subscription call runs first in the slot with fallback `no-key`. The read runner takes `no-key` in issue mode where it takes `credit-stop`: it claims the lease, runs the start gate and re-checks the blockers, and records no skipped-key leg, as a key held off by the switch records none. With the switch off the chain is unchanged.
