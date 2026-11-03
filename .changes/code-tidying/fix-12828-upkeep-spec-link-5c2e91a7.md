---
bump: minor
---

### Added

- `upkeep_spec_issue`, a team setting with no default: the issue holding the upkeep sweep's
  contract, which each upkeep batch pull request links with `Refs: #<n>` so a verifier has a spec to
  judge it against. `upkeep-setting.sh upkeep_spec_issue` reads it, empty when unset or invalid.
