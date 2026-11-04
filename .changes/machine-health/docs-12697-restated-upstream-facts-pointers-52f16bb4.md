---
bump: patch
---

### Changed

- `setup` no longer describes `claude plugin configure`'s install lookup, the rerun's `-s`
  default, or either route's exit code and empty-string handling. It keeps passing the scope
  `claude plugin list` reports and reading each route's output, and points at the
  `plugin configure` and `plugin install` sections of the plugin commands reference.
- The Windows check catalog's environment and PATH health entry no longer explains the User Path
  `CRIT` threshold with a claim about the System Properties editor; 2047 stays as this audit's own
  threshold.
