---
bump: patch
---

### Fixed

- `check-listing-budget.sh`: a `disable-model-invocation` spelled `yes`, `on` or `1`, in any letter
  case, now leaves the listing estimate as `true` does, so such a skill no longer overstates the
  aggregate.
- `check-skill.sh`: `disable-model-invocation` accepts `yes`, `no`, `on`, `off`, `1` and `0` in any
  letter case, as the skills page does, so the two checks agree on those spellings.
