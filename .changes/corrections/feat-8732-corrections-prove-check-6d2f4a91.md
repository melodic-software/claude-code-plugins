---
bump: minor
---

### Added

- The `corrections` plugin, with `scripts/prove-check.sh`: `--check '<command>' --old <ref> [--new <ref>]` runs the check in temporary worktrees at both refs and exits 0 only when it fails at the old ref and passes at the new one (default `HEAD`), 1 when the proof fails, 2 on a usage error, and always removes its worktrees. `scripts/prove-check.test.sh` covers it against a fixture repository.
