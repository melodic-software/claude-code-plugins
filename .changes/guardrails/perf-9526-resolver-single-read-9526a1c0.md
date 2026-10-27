---
bump: patch
---

### Changed

- `resolve-convention-pattern.sh` reads the neutral convention file (`docs/conventions/source-control/commit-convention.yml` or a `convention_source` pointer) once per run with shell builtins, where it ran a `grep` (and a `tr`) for every key lookup and a `dirname` for its directory check. A `git commit` judged with the well-known file tracked and no convention cache skips 12 `grep` and 2 `dirname` processes (#9526). Resolved patterns and exit codes are otherwise unchanged.

### Fixed

- An unreadable neutral convention file now disables enforcement (exit 1) with its own diagnostic, as a missing file or a symlinked pointer does. Before, the resolver fell back to the `.claude/source-control.md` H2 pattern the neutral file was meant to replace.
