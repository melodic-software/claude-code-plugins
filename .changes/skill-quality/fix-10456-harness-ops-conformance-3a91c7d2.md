---
bump: patch
---

### Fixed

- `check-listing-budget.sh`: a `disable-model-invocation` spelled `yes`, `on` or `1`, in any letter
  case, now leaves the listing estimate as `true` does, so such a skill no longer overstates the
  aggregate.
