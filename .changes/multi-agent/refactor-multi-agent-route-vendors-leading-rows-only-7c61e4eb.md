---
bump: major
---

### Removed

- **Breaking:** `vendors.tiebreak` is gone from `multi-agent.schema.json`, so a config that sets it fails validation; delete the key. `resolve-roles.sh` now ignores it as an unknown key, `/multi-agent:setup apply` no longer writes it, and `vendor-decide` no longer takes `--tiebreak` or `--usage`. A consensus tie now always resolves as it did with no tiebreak set: the work stays on Claude unless exactly one non-Claude vendor remains eligible. `/multi-agent:route vendors` no longer reads plan usage (`external-agents usage`, the `rate-limits` status tool).

### Changed

- `/multi-agent:route vendors` fetches, and dispatches a board reader for, only registry rows that can lead (`status` not `support-only`, `provider_own` false). Support-only and provider-own rows are still fetched while trials are active, because their records seed trial candidates. A skipped row is listed in the decision's sources as `not-read` with its link. Registry rechecks (`/multi-agent:audit-defaults registry`) are unchanged.
