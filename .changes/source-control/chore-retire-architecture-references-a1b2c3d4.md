---
bump: minor
---

### Changed

- `owner_decisions_record` is now optional: when unset, cost-hold decisions (`cost_decision`) and spec amendments clearing an earlier verify FAIL (`_spec_amended`) require only a `verbatim:` owner quote (plus the existing unedited trusted-actor checks) instead of refusing every decision when no record is configured.
