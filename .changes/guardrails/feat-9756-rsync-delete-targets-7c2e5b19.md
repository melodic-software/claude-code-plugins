---
bump: minor
---

### Added

- `block-root-delete-target` judges rsync deletes the way it judges a recursive `rm`. With `--del`, `--delete` or a `--delete-<mode>` option the destination, the last operand, is a target; with `--remove-source-files` every source before it is. So `rsync -a --delete src/ /`, a delete into `$HOME` and one outside the allowed roots are refused, and a delete strictly inside the git toplevel, the scratchpad or an allowed root passes. A remote operand (`host:path`, `rsync://`) is left alone.
