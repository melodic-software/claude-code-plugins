---
bump: patch
---

### Changed

- `setup` no longer describes `claude plugin configure`'s install lookup, the rerun's `-s`
  default, or either route's exit code and empty-string handling. It keeps passing the scope
  `claude plugin list` reports and reading each route's output, and points at the
  `plugin configure` and `plugin install` sections of the plugin commands reference.
