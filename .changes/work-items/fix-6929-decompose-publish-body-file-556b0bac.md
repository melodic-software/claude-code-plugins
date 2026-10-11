---
bump: minor
---

### Added

- **`create-item --body-file <path>`.** The tracker dispatcher reads the file and hands the adapter `--body`, so every adapter, bundled or consumer-local, accepts it with no change. `--body` with `--body-file`, or an unreadable or empty file, exits `2`, so a failed Write step cannot publish an item with an empty body.

### Fixed

- **The `/work-items:decompose` publish snippet and the `/work-items:track add` snippet run from a worktree-isolated session (#6929).** Both now pass the body through `--body-file` and spell the tracker path and labels out, one plain command per call, instead of a `$(git rev-parse --show-toplevel)` path fallback and a `"$(cat "$BODY_FILE")"` body, which worktree isolation refused.
