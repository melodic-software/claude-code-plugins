---
bump: minor
---

### Added

- A `pre_ready` list in `docs/conventions/source-control.yaml` turns off any of the five pre-flip steps of `/source-control:pull-request ready` (`base-merge`, `plan-evidence`, `code-review`, `security-review`, `verify`) with `enabled: false`. It is read at the pull request's own base branch in its base repository, never the head, through `scripts/read-pre-ready.sh`. A missing file (a 404) or key runs every step. A failed base read, an unparsable list, or a list the schema would reject (an unknown or repeated step, an extra key, an `enabled` other than unquoted `true` or `false`) also runs every step, and the report says why. The hold checks, the push and the flip always run. With `base-merge` disabled, local commits are still pushed before the reviews, so the reviews and the verify gate cover the same commit. `ready` now reports one line per step: ran and passed, ran and failed, skipped with the built-in condition, or disabled by `pre_ready` at the base branch.
