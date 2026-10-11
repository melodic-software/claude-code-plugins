---
bump: minor
---

### Added

- `/source-control:pull-request view` and `list`: read-only actions other skills call instead of a forge CLI. `view [<pr>] [--diff]` prints one pull request's facts as JSON, with the repository's visibility, or its diff; with no number it reads the current branch's pull request. `list` prints pull requests by head branch (`--head`) or head-branch pattern (`--head-match`), in any state, up to 1000 rows. `--out <file>` writes either output to a file, so a large diff reaches a later gate whole.
