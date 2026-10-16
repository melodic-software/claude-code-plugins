---
bump: minor
---

### Added

- A `pre_ready` list in `docs/conventions/source-control.yaml` turns off any of the five pre-flip steps of `/source-control:pull-request ready` (`base-merge`, `plan-evidence`, `code-review`, `security-review`, `verify`) with `enabled: false`. It is read at the pull request's base branch, never the head, through `scripts/read-pre-ready.sh`; a missing key runs every step, and an unknown or repeated step, a bad value or an unparsable list runs every step and says why. The hold checks, the push and the flip always run. `ready` now reports one line per step: ran and passed, ran and failed, skipped with the built-in condition, or disabled by `pre_ready` at the base branch.
